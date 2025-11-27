# Quick Test Reference

## 🚀 Quick Start Testing

### 1️⃣ Local Test (Docker)

```bash
# Make sure Docker is running first!

# Run automated tests
./apps/calibre/test.sh

# Or manually:
cd apps/calibre/docker
docker build -t calibre-puller:test .
docker run --rm \
  -e REMOTE_OPDS_URL='https://calibrebooks.dwilliams.cloud/opds' \
  -e MAX_BOOKS=3 \
  -e DRY_RUN=1 \
  calibre-puller:test
```

### 2️⃣ Push to Registry

```bash
# Tag
docker tag calibre-puller:test ghcr.io/anh-duy-tran/calibre-puller:latest

# Login (if needed)
echo $GITHUB_TOKEN | docker login ghcr.io -u anh-duy-tran --password-stdin

# Push
docker push ghcr.io/anh-duy-tran/calibre-puller:latest
```

### 3️⃣ Deploy to Kubernetes

```bash
# Deploy via ArgoCD
kubectl apply -f apps/calibre/app.yaml

# Wait for ready
kubectl wait --for=condition=ready pod -l app=calibre-server -n calibre --timeout=300s

# Check status
kubectl get all -n calibre
```

### 4️⃣ Run Test Job

```bash
# Dry run first
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: calibre-test
  namespace: calibre
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: puller
        image: ghcr.io/anh-duy-tran/calibre-puller:latest
        env:
        - {name: REMOTE_OPDS_URL, value: "https://calibrebooks.dwilliams.cloud/opds"}
        - {name: MAX_BOOKS, value: "3"}
        - {name: DRY_RUN, value: "1"}
        - {name: LIBRARY_PATH, value: "/data/calibre-library"}
        volumeMounts:
        - {name: lib, mountPath: /data/calibre-library}
      volumes:
      - name: lib
        persistentVolumeClaim:
          claimName: calibre-library-pvc
EOF

# Watch logs
kubectl logs -n calibre job/calibre-test -f

# If dry run looks good, run actual import
kubectl apply -f apps/calibre/manifests/puller-job-example.yaml
kubectl logs -n calibre job/calibre-pull-poc -f
```

### 5️⃣ Access Web UI

```bash
# Port forward
kubectl port-forward -n calibre svc/calibre-server 8083:8083

# Open: http://localhost:8083
# Login: admin / admin123
# Set library path: /books
```

---

## 🔍 Quick Checks

```bash
# Check pods
kubectl get pods -n calibre

# Check jobs
kubectl get jobs -n calibre

# View logs
kubectl logs -n calibre deployment/calibre-server
kubectl logs -n calibre job/calibre-pull-poc

# Check library contents
kubectl exec -n calibre deployment/calibre-server -- ls -lh /books

# Check PVC
kubectl get pvc -n calibre
kubectl describe pvc calibre-library-pvc -n calibre
```

---

## 🧹 Cleanup

```bash
# Delete test jobs
kubectl delete job -n calibre calibre-test

# Delete everything
kubectl delete application calibre -n argocd
# or
kubectl delete namespace calibre
```

---

## 📝 Full Documentation

- **Detailed Testing**: See `TESTING.md`
- **User Guide**: See `README.md`
- **Quick Deploy**: See `QUICKSTART.md`
