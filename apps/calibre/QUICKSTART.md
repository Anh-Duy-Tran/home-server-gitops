# Calibre Puller - Quick Start Guide

## TL;DR

```bash
# 1. Build and push the image
cd apps/calibre/docker
make build push  # or manually: docker build -t <your-image> . && docker push <your-image>

# 2. Deploy via ArgoCD
kubectl apply -f apps/calibre/app.yaml

# 3. Wait for server to be ready
kubectl wait --for=condition=ready pod -l app=calibre-server -n calibre --timeout=300s

# 4. Run a test job (dry run first!)
kubectl create job calibre-test-dryrun -n calibre \
  --image=ghcr.io/anh-duy-tran/calibre-puller:latest \
  -- /bin/bash -c "
    export REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds'
    export MAX_BOOKS=5
    export DRY_RUN=1
    /usr/local/bin/puller.sh
  "

# 5. Check logs
kubectl logs -n calibre job/calibre-test-dryrun -f

# 6. If dry run looks good, run actual import
kubectl apply -f apps/calibre/manifests/puller-job-example.yaml
kubectl logs -n calibre job/calibre-pull-poc -f

# 7. Access Calibre Web UI
kubectl port-forward -n calibre svc/calibre-server 8083:8083
# Open http://localhost:8083
```

## Pre-requisites Checklist

- [ ] Kubernetes cluster running
- [ ] kubectl configured and working
- [ ] Docker installed locally
- [ ] Access to container registry (GitHub, Docker Hub, etc.)
- [ ] 50Gi storage available in your cluster

## Step-by-Step

### 1. Build the Container Image

```bash
cd apps/calibre/docker

# Option A: Using Makefile
make IMAGE=ghcr.io/YOUR_USERNAME/calibre-puller TAG=latest push

# Option B: Manual
docker build -t ghcr.io/YOUR_USERNAME/calibre-puller:latest .
docker push ghcr.io/YOUR_USERNAME/calibre-puller:latest
```

### 2. Update Image References

If you're not using `ghcr.io/anh-duy-tran/calibre-puller`, update these files:
- `manifests/puller-job-template.yaml`
- `manifests/puller-job-example.yaml`

### 3. Deploy the Server

```bash
# Option A: Via ArgoCD (recommended)
kubectl apply -f apps/calibre/app.yaml

# Option B: Direct apply
kubectl apply -k apps/calibre/manifests/

# Verify
kubectl get pods -n calibre
kubectl get pvc -n calibre
```

### 4. Test with Dry Run

Create a test job to preview what would be downloaded:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-test-dryrun
  namespace: calibre
spec:
  backoffLimit: 2
  template:
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

# Watch the logs
kubectl logs -n calibre job/calibre-test-dryrun -f
```

Expected output:
```
=== Calibre OPDS Puller ===
Remote OPDS URL: https://calibrebooks.dwilliams.cloud/opds
Max books: 3
Library path: /data/calibre-library
Formats filter: epub
Genre filter: none
Dry run: 1

Found 3 candidate book(s) (limited to 3)

=== DRY RUN MODE - Candidate URLs ===
     1	https://calibrebooks.dwilliams.cloud/get/EPUB/123/Book-Title.epub
     2	https://calibrebooks.dwilliams.cloud/get/EPUB/456/Another-Book.epub
     3	https://calibrebooks.dwilliams.cloud/get/EPUB/789/Third-Book.epub

Dry run complete. No books downloaded.
```

### 5. Run Actual Import

If the dry run looks good:

```bash
# Use the provided example
kubectl apply -f apps/calibre/manifests/puller-job-example.yaml

# Monitor progress
kubectl get jobs -n calibre -w
kubectl logs -n calibre job/calibre-pull-poc -f
```

Expected output:
```
=== Calibre OPDS Puller ===
[configuration details]

=== Downloading and importing books ===
----------------------------------------
Processing: https://calibrebooks.dwilliams.cloud/get/EPUB/123/Book-Title.epub
Downloading to /tmp/tmp.xxxxx/Book-Title.epub...
Importing into Calibre library...
SUCCESS: Book imported
----------------------------------------
[... more books ...]

=== Summary ===
Books imported: 5
Books skipped (duplicates): 0
Failed downloads/imports: 0
Total processed: 5

SUCCESS: Imported 5 book(s) into library
```

### 6. Access the Library

```bash
# Port forward
kubectl port-forward -n calibre svc/calibre-server 8083:8083

# Open in browser: http://localhost:8083
```

First login:
- Username: `admin`
- Password: `admin123`

Configure the library path in Calibre-Web settings:
- Database Location: `/books`

## Common Commands

```bash
# List all jobs
kubectl get jobs -n calibre

# Delete completed jobs
kubectl delete job -n calibre calibre-test-dryrun
kubectl delete job -n calibre calibre-pull-poc

# Check library contents
kubectl exec -n calibre deployment/calibre-server -- ls -lh /books

# Check storage usage
kubectl exec -n calibre deployment/calibre-server -- df -h /books

# Restart the server
kubectl rollout restart deployment/calibre-server -n calibre
```

## Troubleshooting

### Job fails immediately
```bash
# Check job status
kubectl describe job -n calibre <job-name>

# Check logs
kubectl logs -n calibre job/<job-name>
```

Common issues:
- Missing `REMOTE_OPDS_URL`: Set in Job env vars
- `MAX_BOOKS` <= 0: Must be > 0
- Image pull errors: Check image name and registry access

### No books imported
```bash
# Verify OPDS feed is accessible
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n calibre -- \
  curl -v https://calibrebooks.dwilliams.cloud/opds

# Run with DRY_RUN=1 to see candidates
```

### PVC not binding
```bash
# Check PVC status
kubectl get pvc -n calibre
kubectl describe pvc calibre-library-pvc -n calibre

# Check available storage classes
kubectl get storageclass
```

### Server not accessible
```bash
# Check pod status
kubectl get pods -n calibre
kubectl describe pod -n calibre -l app=calibre-server

# Check logs
kubectl logs -n calibre deployment/calibre-server
```

## What's Next?

- Schedule regular imports with a CronJob (see README.md)
- Set up ingress for external access
- Configure authentication in Calibre-Web
- Add more OPDS sources
- Monitor storage usage

## Help

For detailed documentation, see [README.md](README.md)
