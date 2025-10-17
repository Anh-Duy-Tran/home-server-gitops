# Velero Backup & Restore Guide

## Overview

Velero backs up Kubernetes resources and persistent volume data to Minio (local S3-compatible storage).

**Automatic Backups:**
- **Schedule**: Daily at 2 AM
- **Namespaces**: `argocd`, `default`
- **Retention**: 30 days (720h)
- **Schedule name**: `velero-daily-backup`

---

## Manual Backup

### Option 1: Using Template File

```bash
cd /Users/duytran/PersonalCloud/k8s

# Edit the timestamp in velero/manual-backup.yaml
# Replace TIMESTAMP with: YYYYMMDD-HHMMSS

kubectl apply -f velero/manual-backup.yaml
```

### Option 2: Direct Command

```bash
kubectl apply -f - <<'EOF'
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: manual-backup-YYYYMMDD-HHMMSS
  namespace: velero
spec:
  includedNamespaces:
    - argocd
    - default
  storageLocation: default
  ttl: 720h0m0s
EOF
```

**Replace `YYYYMMDD-HHMMSS` with current timestamp** (e.g., `20251017-223000`)

---

## Check Backup Status

```bash
# List all backups
kubectl get backups -n velero

# Check specific backup details
kubectl describe backup <backup-name> -n velero

# Watch backup progress
kubectl get backup <backup-name> -n velero -w
```

**Backup Phases:**
- `New` → Backup created
- `InProgress` → Backing up data
- `Completed` → ✅ Success
- `Failed` → ❌ Error (check logs)

---

## Restore from Backup

### Check Available Backups

```bash
kubectl get backups -n velero
```

### Restore Specific Backup

```bash
kubectl apply -f - <<'EOF'
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-YYYYMMDD-HHMMSS
  namespace: velero
spec:
  backupName: manual-backup-20251017-223000
  includedNamespaces:
    - argocd
  restorePVs: true
EOF
```

### Check Restore Status

```bash
# List all restores
kubectl get restores -n velero

# Check specific restore details
kubectl describe restore <restore-name> -n velero
```

---

## View Backups in Minio

1. Get Minio Console URL:
   ```bash
   kubectl get svc -n minio minio-console
   ```

2. Access via LoadBalancer IP
3. Login:
   - **Username**: `minioadmin`
   - **Password**: `minioadmin123`

4. Navigate to bucket: **`velero`**
5. Browse backups: `backups/<backup-name>/`

---

## Troubleshooting

### Check Velero Logs

```bash
kubectl logs -n velero deployment/velero --tail=50
```

### Check Backup Storage Location

```bash
kubectl get backupstoragelocation -n velero
# Should show: Phase: Available
```

### Check Schedule Status

```bash
kubectl get schedules -n velero
# STATUS should be: Enabled
```

### Common Issues

**Backup stuck in "InProgress":**
```bash
kubectl describe backup <backup-name> -n velero | grep -A 10 Events
```

**Minio connection issues:**
```bash
kubectl logs -n velero deployment/velero | grep -i "minio\|s3"
```

---

## Auto-Restore on Cluster Startup

**Configuration**: `/var/lib/k0s/manifests/velero/auto-restore-config.yaml`

```yaml
AUTO_RESTORE: "true"  # Enable/disable auto-restore
RESTORE_MODE: "latest"  # Use latest backup
```

**How it works:**
1. When cluster starts, Velero checks for backups
2. If `AUTO_RESTORE=true` → restores from latest backup
3. ArgoCD comes up with previous data

**To disable:**
Edit `k8s/velero/auto-restore-config.yaml` and set `AUTO_RESTORE: "false"`, then:
```bash
k0sctl apply --config k0sctl.yaml
```

---

## Backup Workflow

### Before Major Changes

```bash
# Create backup before upgrading/changing cluster
kubectl apply -f velero/manual-backup.yaml
# (update timestamp first)

# Wait for completion
kubectl get backup <name> -n velero -w
```

### Disaster Recovery

1. **Deploy new cluster** with `k0sctl apply`
2. **Velero auto-installs** with Minio + schedules
3. **Auto-restore runs** (if enabled) → restores latest backup
4. **Verify restored resources:**
   ```bash
   kubectl get pods -n argocd
   kubectl get pvc -n argocd
   ```

---

## Files Location

- **Schedule definition**: Configured in `k8s/k0sctl.yaml` (Velero Helm values)
- **Manual backup template**: `k8s/velero/manual-backup.yaml`
- **Auto-restore config**: `k8s/velero/auto-restore-config.yaml`
- **Backup storage**: Minio bucket `velero` on node at `/var/openebs/local/`

---

## Quick Reference

```bash
# Manual backup
kubectl apply -f velero/manual-backup.yaml

# List backups
kubectl get backups -n velero

# Restore
kubectl apply -f - <<'EOF'
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-TIMESTAMP
  namespace: velero
spec:
  backupName: <backup-name>
EOF

# Check status
kubectl get backups,restores -n velero
```
