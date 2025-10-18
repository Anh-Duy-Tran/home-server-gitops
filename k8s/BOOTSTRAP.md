# Cluster Bootstrap Guide

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Deploy Cluster](#deploy-cluster)
3. [Fix MinIO Permissions](#fix-minio-permissions)
4. [Configure Docker Hub Credentials (Optional)](#configure-docker-hub-credentials-optional)
5. [Verify Deployment](#verify-deployment)

---

## Prerequisites

- k0sctl installed
- SSH access to target host
- kubectl configured

---

## Deploy Cluster

```bash
cd /Users/duytran/PersonalCloud/k8s
k0sctl apply --config k0sctl.yaml
```

Wait for all pods to be ready (~5 minutes).

---

## Fix MinIO Permissions

**Issue:** MinIO crashes on first deployment due to directory permissions.

**Fix (before k0sctl apply):**
```bash
ssh duytran@192.168.50.240 "sudo mkdir -p /var/k8s-persistent-data/minio && sudo chmod 777 /var/k8s-persistent-data/minio"
```

**Or fix after (if MinIO is crashing):**
```bash
ssh duytran@192.168.50.240 "sudo chmod 777 /var/k8s-persistent-data/minio"
kubectl delete pod -n minio <pod-name>
```

**Why:** PV creates directory as root:root, MinIO runs as UID 1000. Pre-creating with 777 avoids the issue.

---

## Configure Docker Hub Credentials (Optional)

**When needed:** If you hit Docker Hub rate limits (100 pulls/6hrs unauthenticated).

**Error:** `ImagePullBackOff` with `429 Too Many Requests`

**Steps:**

1. **Generate Docker Hub token:**
   - Go to https://hub.docker.com/settings/security
   - Click "New Access Token"
   - Name: `k8s-cluster`
   - Permissions: Read-only
   - Copy the token

2. **Create secret file:**
   ```bash
   cd /Users/duytran/PersonalCloud/k8s/secrets

   kubectl create secret docker-registry dockerhub-secret \
     --docker-server=docker.io \
     --docker-username=duytran410 \
     --docker-password=YOUR_TOKEN_HERE \
     --dry-run=client -o yaml > dockerhub-secret.yaml
   ```

3. **Apply to cluster:**
   ```bash
   kubectl apply -f dockerhub-secret.yaml
   kubectl apply -f patch-serviceaccount-imagepull.yaml
   ```

**Alternative:** Wait ~6 hours for rate limit to reset.

---

## Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Check MinIO is healthy
kubectl logs -n minio deployment/minio

# Check Velero node-agent
kubectl get daemonset -n velero

# Check ArgoCD applications
kubectl get applications -n argocd
```
