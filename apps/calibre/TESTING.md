# Testing Guide - Calibre OPDS Puller

## Phase 1: Local Testing (Docker)

### Step 1: Build the Image

```bash
cd apps/calibre/docker

# Build the image
docker build -t calibre-puller:test .
```

### Step 2: Test Locally with Dry Run

```bash
# Test with the example OPDS feed (dry run mode)
docker run --rm \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=3 \
  -e FORMATS='epub' \
  -e DRY_RUN=1 \
  calibre-puller:test
```

**Expected output:**
```
=== Calibre OPDS Puller ===
Remote OPDS URL: https://calibrebooks.dwilliams.cloud/opds
Max books: 3
Library path: /data/calibre-library
Formats filter: epub
Genre filter: none
Dry run: 1

Fetching OPDS feed from https://calibrebooks.dwilliams.cloud/opds...
Parsing OPDS feed for book entries...
Found 3 candidate book(s) (limited to 3)

=== DRY RUN MODE - Candidate URLs ===
     1	https://calibrebooks.dwilliams.cloud/get/EPUB/123/Book-Title.epub
     2	https://calibrebooks.dwilliams.cloud/get/EPUB/456/Another-Book.epub
     3	https://calibrebooks.dwilliams.cloud/get/EPUB/789/Third-Book.epub

Dry run complete. No books downloaded.
```

### Step 3: Test Validation (Should Fail)

```bash
# Test 1: Missing REMOTE_OPDS_URL (should exit 2)
docker run --rm \
  -e MAX_BOOKS=5 \
  calibre-puller:test
# Expected: "ERROR: REMOTE_OPDS_URL is required"

# Test 2: Invalid MAX_BOOKS (should exit 2)
docker run --rm \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=0 \
  calibre-puller:test
# Expected: "ERROR: MAX_BOOKS must be an integer > 0"

# Test 3: Non-numeric MAX_BOOKS (should exit 2)
docker run --rm \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS='abc' \
  calibre-puller:test
# Expected: "ERROR: MAX_BOOKS must be an integer > 0"
```

### Step 4: Test Real Download (Local Volume)

```bash
# Create local test directory
mkdir -p /tmp/calibre-test-library

# Run with actual download
docker run --rm \
  -v /tmp/calibre-test-library:/data/calibre-library \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=1 \
  -e FORMATS='epub' \
  -e DRY_RUN=0 \
  calibre-puller:test

# Verify books were downloaded
ls -lh /tmp/calibre-test-library/
```

**Expected output:**
```
=== Summary ===
Books imported: 1
Books skipped (duplicates): 0
Failed downloads/imports: 0
Total processed: 1

SUCCESS: Imported 1 book(s) into library
```

**Verify library contents:**
```bash
# Should see metadata.db and book directories
ls -la /tmp/calibre-test-library/
```

### Step 5: Test Duplicate Detection

```bash
# Run the same command again - should skip duplicates
docker run --rm \
  -v /tmp/calibre-test-library:/data/calibre-library \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=1 \
  -e FORMATS='epub' \
  -e DRY_RUN=0 \
  calibre-puller:test
```

**Expected output:**
```
=== Summary ===
Books imported: 0
Books skipped (duplicates): 1
Failed downloads/imports: 0
Total processed: 1

INFO: All books already in library
```

### Cleanup Local Test

```bash
rm -rf /tmp/calibre-test-library
```

---

## Phase 2: Push to Registry

### Option A: GitHub Container Registry

```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Tag the image
docker tag calibre-puller:test ghcr.io/anh-duy-tran/calibre-puller:latest

# Push
docker push ghcr.io/anh-duy-tran/calibre-puller:latest
```

### Option B: Using Makefile

```bash
cd apps/calibre/docker

# Set your registry
export IMAGE=ghcr.io/anh-duy-tran/calibre-puller
export TAG=latest

# Build and push
make push
```

---

## Phase 3: Deploy to Kubernetes

### Step 1: Deploy via ArgoCD

```bash
# Apply the ArgoCD application
kubectl apply -f apps/calibre/app.yaml

# Watch ArgoCD sync
kubectl get application calibre -n argocd -w
```

**Expected output:**
```
NAME      SYNC STATUS   HEALTH STATUS
calibre   Synced        Healthy
```

### Step 2: Verify Resources

```bash
# Check all resources
kubectl get all -n calibre

# Should see:
# - deployment/calibre-server
# - service/calibre-server
# - pvc/calibre-library-pvc
```

### Step 3: Wait for Server to be Ready

```bash
# Wait for PVC to bind
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/calibre-library-pvc -n calibre --timeout=60s

# Wait for server pod to be ready
kubectl wait --for=condition=ready pod -l app=calibre-server -n calibre --timeout=300s

# Check logs
kubectl logs -n calibre deployment/calibre-server --tail=50
```

---

## Phase 4: Test Jobs in Cluster

### Test 1: Dry Run Job

```bash
# Create dry-run test job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-test-dryrun
  namespace: calibre
spec:
  backoffLimit: 2
  template:
    metadata:
      labels:
        app.kubernetes.io/name: calibre
        app.kubernetes.io/component: puller-test
    spec:
      restartPolicy: OnFailure
      containers:
      - name: calibre-puller
        image: ghcr.io/anh-duy-tran/calibre-puller:latest
        env:
        - name: REMOTE_OPDS_URL
          value: "https://calibrebooks.dwilliams.cloud/opds"
        - name: MAX_BOOKS
          value: "3"
        - name: FORMATS
          value: "epub"
        - name: DRY_RUN
          value: "1"
        - name: LIBRARY_PATH
          value: "/data/calibre-library"
        volumeMounts:
        - name: calibre-library
          mountPath: /data/calibre-library
      volumes:
      - name: calibre-library
        persistentVolumeClaim:
          claimName: calibre-library-pvc
EOF

# Watch job progress
kubectl get jobs -n calibre -w

# Check logs (wait for pod to start)
kubectl logs -n calibre job/calibre-test-dryrun -f
```

**Expected log output:**
```
=== Calibre OPDS Puller ===
...
=== DRY RUN MODE - Candidate URLs ===
     1	https://...
     2	https://...
     3	https://...

Dry run complete. No books downloaded.
```

**Verify job succeeded:**
```bash
kubectl get job calibre-test-dryrun -n calibre
# Should show: COMPLETIONS: 1/1
```

### Test 2: Actual Import Job

```bash
# Apply the example job (imports 5 books)
kubectl apply -f apps/calibre/manifests/puller-job-example.yaml

# Monitor progress
kubectl get jobs -n calibre -w

# Watch logs in real-time
kubectl logs -n calibre job/calibre-pull-poc -f
```

**Expected output:**
```
=== Downloading and importing books ===
----------------------------------------
Processing: https://...
Downloading to /tmp/tmp.xxxxx/Book-Title.epub...
Importing into Calibre library...
SUCCESS: Book imported
----------------------------------------
[... repeated for each book ...]

=== Summary ===
Books imported: 5
Books skipped (duplicates): 0
Failed downloads/imports: 0
Total processed: 5

SUCCESS: Imported 5 book(s) into library
```

### Test 3: Verify Books in Library

```bash
# Check library contents from server pod
kubectl exec -n calibre deployment/calibre-server -- ls -lh /books

# Should see:
# - metadata.db
# - Book directories (Author Name/Book Title (ID)/)
```

### Test 4: Access Calibre Web UI

```bash
# Port-forward to access locally
kubectl port-forward -n calibre svc/calibre-server 8083:8083

# Open in browser: http://localhost:8083
```

**First time setup:**
1. Click "Login" (top right)
2. Default credentials: `admin` / `admin123`
3. Go to "Admin" → "Edit Basic Configuration"
4. Set "Location of Calibre database": `/books`
5. Click "Save"
6. You should now see the imported books!

---

## Phase 5: Test Validation & Error Handling

### Test 1: Invalid Config (Missing URL)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-test-no-url
  namespace: calibre
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: calibre-puller
        image: ghcr.io/anh-duy-tran/calibre-puller:latest
        env:
        - name: MAX_BOOKS
          value: "5"
        - name: LIBRARY_PATH
          value: "/data/calibre-library"
        volumeMounts:
        - name: calibre-library
          mountPath: /data/calibre-library
      volumes:
      - name: calibre-library
        persistentVolumeClaim:
          claimName: calibre-library-pvc
EOF

# Check logs - should show error
kubectl logs -n calibre job/calibre-test-no-url
# Expected: "ERROR: REMOTE_OPDS_URL is required"

# Verify exit code 2
kubectl get pod -n calibre -l job-name=calibre-test-no-url -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}'
# Expected: 2
```

### Test 2: Invalid MAX_BOOKS

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-test-zero-books
  namespace: calibre
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: calibre-puller
        image: ghcr.io/anh-duy-tran/calibre-puller:latest
        env:
        - name: REMOTE_OPDS_URL
          value: "https://calibrebooks.dwilliams.cloud/opds"
        - name: MAX_BOOKS
          value: "0"
        - name: LIBRARY_PATH
          value: "/data/calibre-library"
        volumeMounts:
        - name: calibre-library
          mountPath: /data/calibre-library
      volumes:
      - name: calibre-library
        persistentVolumeClaim:
          claimName: calibre-library-pvc
EOF

kubectl logs -n calibre job/calibre-test-zero-books
# Expected: "ERROR: MAX_BOOKS must be an integer > 0"
```

---

## Cleanup Test Resources

```bash
# Delete test jobs
kubectl delete job -n calibre calibre-test-dryrun
kubectl delete job -n calibre calibre-test-no-url
kubectl delete job -n calibre calibre-test-zero-books
kubectl delete job -n calibre calibre-pull-poc

# Or delete all completed jobs
kubectl delete job -n calibre --field-selector status.successful=1

# To completely remove the app
kubectl delete application calibre -n argocd
# Or direct delete
kubectl delete namespace calibre
```

---

## Quick Test Checklist

- [ ] Docker image builds successfully
- [ ] Dry run works locally
- [ ] Validation errors work (exit code 2)
- [ ] Real download works locally
- [ ] Duplicate detection works
- [ ] Image pushed to registry
- [ ] ArgoCD deploys successfully
- [ ] PVC binds and server starts
- [ ] Dry run job succeeds in cluster
- [ ] Import job downloads books
- [ ] Books visible in Calibre Web UI
- [ ] Invalid config jobs fail correctly

---

## Troubleshooting

### Issue: PVC Won't Bind

```bash
kubectl describe pvc calibre-library-pvc -n calibre
# Check for storage class issues or quota limits
```

### Issue: Image Pull Errors

```bash
kubectl describe pod -n calibre <pod-name>
# Check imagePullPolicy and registry authentication
```

### Issue: Job Fails Immediately

```bash
kubectl logs -n calibre job/<job-name>
kubectl describe job -n calibre <job-name>
```

### Issue: OPDS Feed Not Accessible

```bash
# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n calibre -- \
  curl -v https://calibrebooks.dwilliams.cloud/opds
```

### Issue: Books Not Showing in Web UI

```bash
# Check calibre-web config
kubectl exec -n calibre deployment/calibre-server -- cat /config/app.db
# Verify library path is set to /books

# Check actual library contents
kubectl exec -n calibre deployment/calibre-server -- ls -la /books
```

---

## Performance Testing (Optional)

### Test Large Batch

```bash
# Test with 50 books (adjust MAX_BOOKS)
# Monitor resources
kubectl top pods -n calibre
kubectl top nodes
```

### Test Concurrent Jobs (Not Recommended for RWO PVC)

```bash
# This WILL fail due to RWO PVC - only one pod can mount at a time
# The second job will hang waiting for PVC to be available
```

---

## Next Steps After Testing

Once all tests pass:
1. Update `MAX_BOOKS` to your desired default
2. Consider creating a CronJob for scheduled imports
3. Set up monitoring/alerts
4. Configure backup for the PVC
5. Set up ingress for external access to calibre-web
