# Cluster Bootstrap Steps

## First-Time Setup Only

**Issue:** MinIO crashes on first deployment due to directory permissions.

**Fix:**
```bash
ssh duytran@192.168.50.240 "sudo chmod 777 /var/k8s-persistent-data/minio"
kubectl delete pod -n minio <pod-name>
```

**Why:** PV creates directory as root:root, MinIO runs as UID 1000. Permissions persist after fix.
