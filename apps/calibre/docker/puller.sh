#!/usr/bin/env bash
set -euo pipefail

# Read configuration from environment
REMOTE="${REMOTE_OPDS_URL:-}"
MAX="${MAX_BOOKS:-0}"
LIB="${LIBRARY_PATH:-/data/calibre-library}"
FORMATS="${FORMATS:-}"
GENRE="${FILTER_GENRE:-}"
DRY="${DRY_RUN:-0}"

# Validation
if [[ -z "$REMOTE" ]]; then
  echo "ERROR: REMOTE_OPDS_URL is required"
  exit 2
fi

if ! [[ "$MAX" =~ ^[0-9]+$ ]] || (( MAX <= 0 )); then
  echo "ERROR: MAX_BOOKS must be an integer > 0 (got: $MAX)"
  exit 2
fi

echo "=== Calibre OPDS Puller ==="
echo "Remote OPDS URL: $REMOTE"
echo "Max books: $MAX"
echo "Library path: $LIB"
echo "Formats filter: ${FORMATS:-none}"
echo "Genre filter: ${GENRE:-none}"
echo "Dry run: $DRY"
echo

# Create temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Initialize library if it doesn't exist
if [[ ! -d "$LIB" ]] || [[ ! -f "$LIB/metadata.db" ]]; then
  echo "Initializing Calibre library at $LIB..."
  mkdir -p "$LIB"
  calibredb --with-library "$LIB" list || true
fi

# Fetch OPDS feed
echo "Fetching OPDS feed from $REMOTE..."
if ! curl -fsSL --connect-timeout 10 --max-time 30 -o "$TMPDIR/opds.xml" "$REMOTE"; then
  echo "ERROR: Failed to fetch OPDS feed"
  exit 1
fi

# Parse OPDS feed for download links
# Look for acquisition links with supported formats
echo "Parsing OPDS feed for book entries..."

# Extract acquisition links using xmllint or grep
# For PoC: use simple grep-based parsing
grep -Eo 'href="[^"]+"' "$TMPDIR/opds.xml" | \
  sed 's/href="//;s/"$//' | \
  grep -E '\.(epub|mobi|azw3|pdf)(\?|$)' > "$TMPDIR/all_links.txt" || true

# Apply format filter if specified
if [[ -n "$FORMATS" ]]; then
  FORMAT_REGEX=$(echo "$FORMATS" | tr ',' '|')
  grep -Ei "\.($FORMAT_REGEX)(\?|$)" "$TMPDIR/all_links.txt" > "$TMPDIR/filtered_links.txt" || true
else
  cp "$TMPDIR/all_links.txt" "$TMPDIR/filtered_links.txt"
fi

# Genre filtering is more complex - would need to parse XML properly
# For PoC, skip genre filtering in the script
if [[ -n "$GENRE" ]]; then
  echo "WARNING: Genre filtering not implemented in PoC - ignoring FILTER_GENRE"
fi

# Limit to MAX_BOOKS
head -n "$MAX" "$TMPDIR/filtered_links.txt" > "$TMPDIR/candidates.txt" || true

CAND_COUNT=$(wc -l < "$TMPDIR/candidates.txt" | tr -d ' ')
echo "Found $CAND_COUNT candidate book(s) (limited to $MAX)"
echo

if [[ "$CAND_COUNT" -eq 0 ]]; then
  echo "No books found matching criteria"
  exit 0
fi

# Dry run mode - just list candidates
if [[ "$DRY" == "1" ]]; then
  echo "=== DRY RUN MODE - Candidate URLs ==="
  nl -ba "$TMPDIR/candidates.txt"
  echo
  echo "Dry run complete. No books downloaded."
  exit 0
fi

# Download and import books
echo "=== Downloading and importing books ==="
IMPORTED=0
FAILED=0
SKIPPED=0

while read -r url; do
  echo "----------------------------------------"
  echo "Processing: $url"

  # Handle relative URLs
  if [[ "$url" =~ ^/ ]]; then
    # Extract base URL from REMOTE_OPDS_URL
    BASE_URL=$(echo "$REMOTE" | sed -E 's|(https?://[^/]+).*|\1|')
    url="${BASE_URL}${url}"
    echo "Resolved to: $url"
  fi

  # Extract filename
  fname=$(basename "$url" | sed 's/?.*//')
  if [[ -z "$fname" ]] || [[ "$fname" == "/" ]]; then
    fname="book_${IMPORTED}.epub"
  fi

  dest="$TMPDIR/$fname"

  # Download
  echo "Downloading to $dest..."
  if ! curl -fsSL --connect-timeout 10 --max-time 60 --fail -o "$dest" "$url"; then
    echo "ERROR: Download failed for $url"
    ((FAILED++))
    continue
  fi

  # Verify file is not empty
  if [[ ! -s "$dest" ]]; then
    echo "ERROR: Downloaded file is empty"
    ((FAILED++))
    rm -f "$dest"
    continue
  fi

  # Import into Calibre library
  echo "Importing into Calibre library..."
  if calibredb add --with-library "$LIB" "$dest" 2>&1 | tee "$TMPDIR/import.log"; then
    echo "SUCCESS: Book imported"
    ((IMPORTED++))
    rm -f "$dest"
  else
    if grep -q "already exists" "$TMPDIR/import.log"; then
      echo "SKIPPED: Book already exists in library"
      ((SKIPPED++))
    else
      echo "ERROR: Import failed"
      ((FAILED++))
    fi
    rm -f "$dest"
  fi

  # Stop if we've reached MAX_BOOKS successful imports
  if (( IMPORTED >= MAX )); then
    echo "Reached maximum books limit ($MAX)"
    break
  fi

done < "$TMPDIR/candidates.txt"

echo
echo "=== Summary ==="
echo "Books imported: $IMPORTED"
echo "Books skipped (duplicates): $SKIPPED"
echo "Failed downloads/imports: $FAILED"
echo "Total processed: $((IMPORTED + SKIPPED + FAILED))"
echo

if (( IMPORTED > 0 )); then
  echo "SUCCESS: Imported $IMPORTED book(s) into library"
  exit 0
elif (( SKIPPED > 0 )); then
  echo "INFO: All books already in library"
  exit 0
else
  echo "ERROR: No books were imported"
  exit 1
fi
