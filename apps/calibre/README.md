# Calibre OPDS Puller - Proof of Concept

A minimal Kubernetes-based system for pulling books from remote OPDS feeds into a local Calibre library.

## Architecture

```
┌─────────────────────┐
│  OPDS Feed Source   │
│  (Remote Server)    │
└──────────┬──────────┘
           │ HTTPS
           ▼
┌─────────────────────┐
│  calibre-puller     │
│  (Kubernetes Job)   │
│  - Fetches OPDS     │
│  - Downloads books  │
│  - Imports via      │
│    calibredb        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  PersistentVolume   │
│  /calibre-library   │
│  (50Gi)             │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  calibre-server     │
│  (Deployment)       │
│  - Serves OPDS      │
│  - Web interface    │
│  Port: 8083         │
└─────────────────────┘
```

## Components

### 1. calibre-server (Deployment)
- **Image**: `linuxserver/calibre-web:latest`
- **Purpose**: Serves the Calibre library via web UI and OPDS
- **Port**: 8083
- **Storage**: Mounts PVC at `/books`

### 2. calibre-puller (Job)
- **Image**: `ghcr.io/anh-duy-tran/calibre-puller:latest`
- **Purpose**: Downloads books from remote OPDS feed and imports to library
- **Storage**: Mounts same PVC at `/data/calibre-library`

### 3. PersistentVolumeClaim
- **Size**: 50Gi
- **Access**: ReadWriteOnce
- **StorageClass**: do-block-storage

## Prerequisites

- Kubernetes cluster (k0s on DigitalOcean in this setup)
- kubectl configured
- Docker for building the puller image
- GitHub account for container registry (or use Docker Hub)

## Quick Start

### Step 1: Build and Push the Puller Image

```bash
cd apps/calibre/docker

# Build the image
docker build -t ghcr.io/YOUR_USERNAME/calibre-puller:latest .

# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Push the image
docker push ghcr.io/YOUR_USERNAME/calibre-puller:latest
```

**Note**: Update the image reference in the Job manifests if using a different registry.

### Step 2: Deploy the Server

```bash
# Apply all base resources (namespace, PVC, server)
kubectl apply -k apps/calibre/manifests/

# Verify deployment
kubectl get pods -n calibre
kubectl get pvc -n calibre
```

Wait for the calibre-server pod to be running:
```bash
kubectl wait --for=condition=ready pod -l app=calibre-server -n calibre --timeout=300s
```

### Step 3: Run a Test Job (Dry Run)

First, test with dry run mode to see what would be downloaded:

```bash
# Create a dry-run job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-pull-dryrun
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
          value: "5"
        - name: FORMATS
          value: "epub"
        - name: LIBRARY_PATH
          value: "/data/calibre-library"
        - name: DRY_RUN
          value: "1"
        volumeMounts:
        - name: calibre-library
          mountPath: /data/calibre-library
      volumes:
      - name: calibre-library
        persistentVolumeClaim:
          claimName: calibre-library-pvc
EOF

# Watch the logs
kubectl logs -n calibre job/calibre-pull-dryrun -f
```

### Step 4: Run the Actual Import

If the dry run looks good, run the actual import:

```bash
# Apply the example job
kubectl apply -f apps/calibre/manifests/puller-job-example.yaml

# Monitor the job
kubectl get jobs -n calibre -w

# Check logs
kubectl logs -n calibre job/calibre-pull-poc -f
```

### Step 5: Access the Calibre Server

```bash
# Port-forward to access the web UI
kubectl port-forward -n calibre svc/calibre-server 8083:8083

# Open in browser: http://localhost:8083
```

Default credentials (first login):
- Username: `admin`
- Password: `admin123`

## Configuration Reference

### Environment Variables (calibre-puller)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REMOTE_OPDS_URL` | **Yes** | - | URL of the remote OPDS feed |
| `MAX_BOOKS` | **Yes** | - | Maximum number of books to download (must be > 0) |
| `FORMATS` | No | All | Comma-separated list of formats (epub,mobi,pdf,azw3) |
| `FILTER_GENRE` | No | - | Genre filter (not implemented in PoC) |
| `LIBRARY_PATH` | No | `/data/calibre-library` | Path to Calibre library directory |
| `DRY_RUN` | No | `0` | Set to `1` to preview without downloading |

### Validation Rules

The puller will **fail immediately** if:
- `REMOTE_OPDS_URL` is empty
- `MAX_BOOKS` is missing, not a number, or <= 0

### Exit Codes

- `0`: Success (books imported or dry run completed)
- `1`: Runtime error (no books imported, download failures)
- `2`: Configuration error (invalid parameters)

## Example Jobs

### Download 5 EPUBs
```yaml
env:
- name: REMOTE_OPDS_URL
  value: "https://calibrebooks.dwilliams.cloud/opds"
- name: MAX_BOOKS
  value: "5"
- name: FORMATS
  value: "epub"
- name: DRY_RUN
  value: "0"
```

### Dry Run with Multiple Formats
```yaml
env:
- name: REMOTE_OPDS_URL
  value: "https://calibrebooks.dwilliams.cloud/opds"
- name: MAX_BOOKS
  value: "10"
- name: FORMATS
  value: "epub,mobi,pdf"
- name: DRY_RUN
  value: "1"
```

### Download Single Book
```yaml
env:
- name: REMOTE_OPDS_URL
  value: "https://calibrebooks.dwilliams.cloud/opds"
- name: MAX_BOOKS
  value: "1"
- name: FORMATS
  value: "epub"
```

## Troubleshooting

### Job Fails with "REMOTE_OPDS_URL is required"
Make sure you set the `REMOTE_OPDS_URL` environment variable in the Job spec.

### Job Fails with "MAX_BOOKS must be an integer > 0"
Verify `MAX_BOOKS` is set to a positive integer (e.g., "5", not "0" or "-1").

### No Books Downloaded
1. Check the OPDS feed is accessible:
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl -v https://calibrebooks.dwilliams.cloud/opds
   ```

2. Run with `DRY_RUN=1` to see candidate URLs

3. Check job logs for errors:
   ```bash
   kubectl logs -n calibre job/calibre-pull-poc
   ```

### Books Already Exist
The puller detects duplicates. Check the summary output:
```
=== Summary ===
Books imported: 0
Books skipped (duplicates): 5
Failed downloads/imports: 0
```

### PVC Not Mounting
Check PVC status:
```bash
kubectl get pvc -n calibre
kubectl describe pvc calibre-library-pvc -n calibre
```

Ensure DigitalOcean block storage is available in your region.

## Operational Notes

### Running Jobs Periodically

To schedule regular imports, create a CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: calibre-puller-daily
  namespace: calibre
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
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
              value: "10"
            - name: FORMATS
              value: "epub"
            - name: LIBRARY_PATH
              value: "/data/calibre-library"
            volumeMounts:
            - name: calibre-library
              mountPath: /data/calibre-library
          volumes:
          - name: calibre-library
            persistentVolumeClaim:
              claimName: calibre-library-pvc
```

### Cleaning Up Failed Jobs

```bash
# Delete completed jobs
kubectl delete job -n calibre --field-selector status.successful=1

# Delete failed jobs
kubectl delete job -n calibre --field-selector status.successful=0
```

### Monitoring Storage Usage

```bash
# Check PVC usage
kubectl exec -n calibre deployment/calibre-server -- df -h /books

# List books in library
kubectl exec -n calibre deployment/calibre-server -- \
  ls -lh /books
```

## Limitations (PoC)

This is a minimal proof-of-concept with the following limitations:

1. **No Genre Filtering**: `FILTER_GENRE` is ignored (would require proper XML parsing)
2. **Simple OPDS Parsing**: Uses grep/sed instead of proper OPDS library
3. **No Authentication**: No support for authenticated OPDS feeds
4. **No Retry Logic**: Failed downloads are logged but not retried
5. **No Rate Limiting**: No throttling of downloads
6. **No DRM Support**: Cannot handle DRM-protected books
7. **No Conversion**: Books imported as-is, no format conversion
8. **RWO Storage**: Only one pod can mount the PVC (server OR puller, not both)

## Future Enhancements

For production use, consider:

- Use a proper OPDS client library (Python `requests` + `feedparser` or `lxml`)
- Add authentication support (HTTP Basic, OAuth)
- Implement genre/category filtering via XML parsing
- Add retry logic with exponential backoff
- Add rate limiting to be friendly to remote servers
- Support for multiple OPDS feeds (ConfigMap or CRD)
- Metrics and monitoring (Prometheus exporter)
- Helm chart for easier deployment
- ReadWriteMany storage for concurrent access
- Operator/CRD for declarative feed management

## Security Notes

- The puller runs as non-root user (UID 1000)
- No secrets exposed in logs
- Uses official Calibre installer
- HTTPS recommended for OPDS feeds
- Consider using Kubernetes Secrets for authenticated feeds

## License

This is a proof-of-concept. Adjust licensing as needed for your use case.

## Support

For issues:
1. Check logs: `kubectl logs -n calibre job/<job-name>`
2. Verify configuration: `kubectl describe job -n calibre <job-name>`
3. Test OPDS feed manually: `curl -v <REMOTE_OPDS_URL>`
