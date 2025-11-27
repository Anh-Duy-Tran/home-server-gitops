#!/bin/bash
set -e

echo "=========================================="
echo "Calibre OPDS Puller - Test Script"
echo "=========================================="
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cd "$(dirname "$0")/docker"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
docker build -t calibre-puller:test .
echo -e "${GREEN}✓ Build successful${NC}"
echo

echo -e "${YELLOW}Step 2: Testing validation (should fail)...${NC}"
echo "Test 2a: Missing REMOTE_OPDS_URL"
if docker run --rm -e MAX_BOOKS=5 calibre-puller:test 2>&1 | grep -q "REMOTE_OPDS_URL is required"; then
    echo -e "${GREEN}✓ Validation test passed (missing URL detected)${NC}"
else
    echo -e "${RED}✗ Validation test failed${NC}"
    exit 1
fi

echo "Test 2b: Invalid MAX_BOOKS=0"
if docker run --rm -e REMOTE_OPDS_URL='https://example.com' -e MAX_BOOKS=0 calibre-puller:test 2>&1 | grep -q "MAX_BOOKS must be"; then
    echo -e "${GREEN}✓ Validation test passed (invalid MAX_BOOKS detected)${NC}"
else
    echo -e "${RED}✗ Validation test failed${NC}"
    exit 1
fi
echo

echo -e "${YELLOW}Step 3: Testing dry run with real OPDS feed...${NC}"
docker run --rm \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=3 \
  -e FORMATS='epub' \
  -e DRY_RUN=1 \
  calibre-puller:test

echo
echo -e "${GREEN}✓ Dry run test completed${NC}"
echo

echo -e "${YELLOW}Step 4: Testing actual download (1 book)...${NC}"
echo "Creating temp library directory..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

docker run --rm \
  -v "$TMPDIR:/data/calibre-library" \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=1 \
  -e FORMATS='epub' \
  -e DRY_RUN=0 \
  calibre-puller:test

echo
if [ -f "$TMPDIR/metadata.db" ]; then
    echo -e "${GREEN}✓ Book import successful (metadata.db created)${NC}"
    echo "Library contents:"
    ls -lh "$TMPDIR/"
else
    echo -e "${RED}✗ Book import failed (no metadata.db)${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Step 5: Testing duplicate detection...${NC}"
docker run --rm \
  -v "$TMPDIR:/data/calibre-library" \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=1 \
  -e FORMATS='epub' \
  -e DRY_RUN=0 \
  calibre-puller:test

echo
echo "=========================================="
echo -e "${GREEN}All tests passed!${NC}"
echo "=========================================="
echo
echo "Next steps:"
echo "1. Tag and push the image:"
echo "   docker tag calibre-puller:test ghcr.io/anh-duy-tran/calibre-puller:latest"
echo "   docker push ghcr.io/anh-duy-tran/calibre-puller:latest"
echo
echo "2. Deploy to Kubernetes:"
echo "   kubectl apply -f apps/calibre/app.yaml"
echo
echo "3. See TESTING.md for detailed cluster testing steps"
