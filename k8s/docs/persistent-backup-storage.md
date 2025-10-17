# Persistent Backup Storage Across Cluster Resets

## The Problem

**When using dynamic OpenEBS PVCs**, each cluster deployment creates new PVCs with random IDs:

```
Deploy 1: Minio at /var/openebs/local/pvc-abc123/
  └─ Backup created ✅

Reset cluster ❌

Deploy 2: Minio at /var/openebs/local/pvc-xyz789/  ← NEW directory, empty!
  └─ Backup NOT found ❌
  └─ Auto-restore fails ❌
```

**Old backup data remains on disk but is orphaned** - new Minio can't access it.

## The Solution

**Use a static PersistentVolume** with a fixed path that survives cluster resets:

```
Fixed path: /var/k8s-persistent-data/minio
  ├─ Deploy, reset, redeploy... same path!
  └─ Backups always accessible ✅
```

---

## Setup (One-Time)

### Step 1: Migrate Existing Backup Data

If you have old backups to preserve:

```bash
cd /Users/duytran/PersonalCloud/k8s
./migrate-minio-data.sh
```

This script:
- Finds old Minio backup data
- Copies to fixed path: `/var/k8s-persistent-data/minio`
- Sets correct permissions

### Step 2: Deploy with Static PV

The k0sctl.yaml is already configured:

```bash
k0sctl apply --config k0sctl.yaml
```

This deploys:
- **Static PV**: `/var/k8s-persistent-data/minio` (survives resets)
- **Minio**: Uses existingClaim (binds to static PV)
- **Velero**: Connects to Minio
- **Auto-restore**: Finds backups and restores

---

## How It Works

### Static PV Configuration

**File**: `minio-persistent-pv.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-data-pv
spec:
  capacity:
    storage: 50Gi
  persistentVolumeReclaimPolicy: Retain  # KEY: Don't delete!
  hostPath:
    path: /var/k8s-persistent-data/minio  # Fixed path
```

**Key settings:**
- `persistentVolumeReclaimPolicy: Retain` - Data survives PVC deletion
- `hostPath: /var/k8s-persistent-data/minio` - Fixed location

### Minio Configuration

**In k0sctl.yaml:**

```yaml
minio:
  persistence:
    enabled: true
    existingClaim: minio  # Use static PVC, don't create new one
```

---

## Disaster Recovery Workflow

### Before Major Changes

```bash
# Create backup
kubectl apply -f velero/manual-backup.yaml
# (update timestamp first)

# Verify
kubectl get backups -n velero
```

### Tear Down & Rebuild

```bash
# 1. Tear down cluster
k0sctl reset

# 2. Redeploy (uses same Minio path)
k0sctl apply --config k0sctl.yaml

# 3. Auto-restore runs automatically
# Wait 2-3 minutes for Velero to initialize

# 4. Verify restoration
kubectl get backups -n velero  # Should show old backups
kubectl get pods -n argocd      # Should have restored data
```

---

## Verification

### Check Static PV Binding

```bash
kubectl get pv minio-data-pv
# Should show: CLAIM=minio/minio, STATUS=Bound
```

### Check Minio Data Location

```bash
ssh duytran@192.168.50.240 "ls -la /var/k8s-persistent-data/minio/velero/backups/"
# Should list your backups
```

### Check Velero Can See Backups

```bash
kubectl get backups -n velero
# Should show backups from before cluster reset
```

---

## Backup Data Location

**Fixed path on node**: `/var/k8s-persistent-data/minio/`

```
/var/k8s-persistent-data/minio/
├── .minio.sys/          # Minio system files
├── velero/
│   └── backups/
│       ├── manual-backup-20251017-223000/
│       ├── daily-backup-20251018-020000/
│       └── ...
└── k8s-backups/         # Optional additional bucket
```

**This directory survives:**
- ✅ Cluster resets (`k0sctl reset`)
- ✅ Node reboots
- ✅ Minio pod restarts
- ❌ Manual deletion of `/var/k8s-persistent-data/`

---

## Cloud Sync (Optional Future)

To also backup to cloud S3:

1. Configure Minio mirror to AWS S3
2. Or use Velero with multiple BackupStorageLocations:

```yaml
# Local (Minio)
backupStorageLocation:
  - name: default
    provider: aws
    bucket: velero
    config:
      s3Url: http://minio.minio:9000

# Cloud (AWS S3)
  - name: aws
    provider: aws
    bucket: my-s3-bucket
    config:
      region: us-east-1
```

Then specify location when backing up:
```bash
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: cloud-backup-$(date +%Y%m%d)
  namespace: velero
spec:
  storageLocation: aws  # Use cloud
  includedNamespaces: ["*"]
EOF
```

---

## Cleanup Old PVC Directories

After migration, you can clean up old orphaned directories:

```bash
ssh duytran@192.168.50.240

# List old directories
ls -la /var/openebs/local/

# Remove old Minio PVCs (be careful!)
sudo rm -rf /var/openebs/local/pvc-c572c3a4-3590-426a-8009-946388f24f51
# etc...
```

**⚠️ Only delete after:**
1. Verifying migration was successful
2. Confirming backups work
3. Creating a new backup after migration

---

## Troubleshooting

### Backups Not Found After Reset

```bash
# Check if data exists on node
ssh duytran@192.168.50.240 "ls -la /var/k8s-persistent-data/minio/velero/backups/"

# Check PV binding
kubectl get pv minio-data-pv
kubectl get pvc -n minio

# Check Minio logs
kubectl logs -n minio deployment/minio
```

### Auto-Restore Failed

```bash
# Check auto-restore job
kubectl get job -n velero velero-auto-restore

# Check job logs
kubectl logs -n velero job/velero-auto-restore --all-containers=true

# Manually trigger restore
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: manual-restore
  namespace: velero
spec:
  backupName: <backup-name>
EOF
```

### Permission Issues

```bash
# Fix permissions on node
ssh duytran@192.168.50.240 "sudo chown -R 1000:1000 /var/k8s-persistent-data/minio"
```

---

## Summary

**Before (Dynamic PVCs):**
- ❌ Each deployment = new directory
- ❌ Old backups orphaned
- ❌ Auto-restore fails

**After (Static PV):**
- ✅ Fixed directory survives resets
- ✅ Backups always accessible
- ✅ Auto-restore works

**Migration needed only once** - after that, everything automatic!
