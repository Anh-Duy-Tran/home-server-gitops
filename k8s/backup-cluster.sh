#!/bin/bash
set -e

echo "=== Manual Cluster Backup ==="
echo "Backing up namespaces: argocd, default"
echo ""

# Check if velero is installed
if ! kubectl get namespace velero &>/dev/null; then
  echo "Error: Velero is not installed. Please run 'k0sctl apply' first."
  exit 1
fi

# Create backup with timestamp
BACKUP_NAME="cluster-backup-$(date +%Y%m%d-%H%M%S)"

echo "Creating backup: $BACKUP_NAME"
velero backup create $BACKUP_NAME \
  --include-namespaces argocd,default \
  --wait

# Show backup status
echo ""
echo "✅ Backup created: $BACKUP_NAME"
echo ""
velero backup get

echo ""
echo "📦 Backup stored in Minio (local S3)"
echo "   Auto-restore will use this on next deployment"
echo ""
echo "Note: Automatic daily backups run at 2 AM"
