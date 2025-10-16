# Visitor Counter - OpenEBS Persistence Demo

A simple visitor counter app that demonstrates persistent storage with OpenEBS.

## Features

- Counts every page visit
- Stores count in `/data/counter.txt` on an OpenEBS PersistentVolume
- Data persists across pod restarts and deletions
- Accessible at `counter.duytran.app`

## How It Works

1. **PVC Creation**: Creates a PersistentVolumeClaim using `openebs-hostpath` StorageClass
2. **Volume Mount**: Mounts the PVC to `/data` inside the container
3. **Data Persistence**: Counter data is stored in `/data/counter.txt`
4. **OpenEBS**: Stores actual data in `/var/openebs/local/` on the host machine

## Build & Deploy

### 1. Build and push Docker image:
```bash
cd apps/visitor-counter
docker build -t duytran410/visitor-counter:latest .
docker push duytran410/visitor-counter:latest
```

### 2. Deploy via ArgoCD:
```bash
kubectl apply -f visitor-counter.argoproj.yaml
```

Or manually:
```bash
kubectl apply -k manifests/
```

## Testing Persistence

### Test 1: Pod Restart
```bash
# Visit the app a few times
curl http://counter.duytran.app

# Delete the pod
kubectl delete pod -l app=visitor-counter

# Visit again - counter should continue from where it left off!
curl http://counter.duytran.app
```

### Test 2: Check the PVC
```bash
# View the PersistentVolumeClaim
kubectl get pvc visitor-counter-data

# View the actual PersistentVolume
kubectl get pv

# Check where data is stored on host
kubectl exec -it $(kubectl get pod -l app=visitor-counter -o jsonpath='{.items[0].metadata.name}') -- cat /data/counter.txt
```

### Test 3: Reset Counter
```bash
curl http://counter.duytran.app/reset
```

## Endpoints

- `GET /` - Main page (increments counter)
- `GET /health` - Health check (returns current count)
- `GET /reset` - Reset counter to 0

## What Happens During Cluster Reset

1. **Before reset**: Data is in `/var/openebs/local/pvc-xxxxx/` on host
2. **After `k0sctl reset`**: Kubernetes cluster is destroyed but `/var/openebs/local/` remains
3. **After redeployment**: OpenEBS recreates the PV and reconnects to existing data
4. **Result**: Counter continues from previous value!

**Note**: This works because OpenEBS stores data OUTSIDE the k0s directory (`/var/lib/k0s/`).
