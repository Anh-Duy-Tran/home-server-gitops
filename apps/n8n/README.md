# n8n - Workflow Automation

n8n is a fair-code licensed workflow automation tool that allows you to connect various services and create automated workflows.

## Overview

This deployment uses **official n8n Docker images** with plain Kubernetes manifests (no third-party Helm charts). All configuration is managed via Kustomize.

## Configuration

### Key Settings

- **Namespace**: `n8n`
- **Image**: `n8nio/n8n:latest` (official n8n image)
- **Storage**: 10Gi persistent volume using `openebs-hostpath`
- **Ingress**: Enabled with Traefik ingress controller
- **Host**: `n8n.duytran.app`
- **Port**: 5678

### Resource Limits

- CPU: 100m request / 1000m limit
- Memory: 256Mi request / 1Gi limit

### Environment Variables

- `N8N_HOST`: n8n.duytran.app
- `N8N_PROTOCOL`: http
- `WEBHOOK_URL`: https://n8n.duytran.app/
- `GENERIC_TIMEZONE`: UTC

## Directory Structure

```
apps/n8n/
├── app.yaml              # ArgoCD application
├── README.md             # This file
└── manifests/
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── pvc.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

## Deployment

Deploy n8n via ArgoCD:

```bash
kubectl apply -f apps/n8n/app.yaml
```

Check deployment status:

```bash
# Check ArgoCD application status
kubectl get application n8n -n argocd

# Check pods
kubectl get pods -n n8n

# Check logs
kubectl logs -n n8n deployment/n8n -f
```

## Access

### Local Access (Port Forward)

```bash
kubectl port-forward -n n8n svc/n8n 5678:5678
```

Then open http://localhost:5678

### Ingress Access

If DNS is configured for `n8n.duytran.app`, access via:

- http://n8n.duytran.app

## Initial Setup

On first access, you'll need to:

1. Create an owner account
2. Set up your email and password
3. Configure any integrations you need

## Storage

n8n data is persisted in a 10Gi PVC at `/home/node/.n8n`:

- Workflows
- Credentials (encrypted)
- Execution history
- Settings

To check storage:

```bash
kubectl get pvc -n n8n
```

## Upgrading

To upgrade n8n to a newer version, update the image tag in `manifests/deployment.yaml`:

```yaml
spec:
  template:
    spec:
      containers:
        - name: n8n
          image: n8nio/n8n:1.19.0 # Specify version instead of :latest
```

Then commit and push - ArgoCD will auto-sync.

**Recommended**: Pin to specific versions instead of using `:latest` for production.

Available versions: https://hub.docker.com/r/n8nio/n8n/tags

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n n8n
kubectl describe pod -n n8n <pod-name>
```

### View Logs

```bash
kubectl logs -n n8n deployment/n8n --tail=100 -f
```

### Check PVC

```bash
kubectl get pvc -n n8n
kubectl describe pvc n8n-data -n n8n
```

### Common Issues

1. **Pod not starting**: Check storage provisioner is available

   ```bash
   kubectl get sc openebs-hostpath
   ```

2. **Ingress not working**: Verify Traefik is running

   ```bash
   kubectl get pods -n traefik
   ```

3. **Data not persisting**: Check PVC is bound

   ```bash
   kubectl get pvc -n n8n
   # Should show STATUS: Bound
   ```

4. **Permission issues**: n8n runs as user `node` (UID 1000), ensure PVC permissions are correct

## Advanced Configuration

### Using PostgreSQL Instead of SQLite

For production, consider using PostgreSQL. Update `manifests/deployment.yaml`:

```yaml
env:
  - name: DB_TYPE
    value: "postgresdb"
  - name: DB_POSTGRESDB_HOST
    value: "postgres.n8n.svc.cluster.local"
  - name: DB_POSTGRESDB_PORT
    value: "5432"
  - name: DB_POSTGRESDB_DATABASE
    value: "n8n"
  - name: DB_POSTGRESDB_USER
    valueFrom:
      secretKeyRef:
        name: n8n-postgres
        key: username
  - name: DB_POSTGRESDB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: n8n-postgres
        key: password
```

### Enable Queue Mode (Redis)

For better scalability with multiple workers:

```yaml
env:
  - name: EXECUTIONS_MODE
    value: "queue"
  - name: QUEUE_BULL_REDIS_HOST
    value: "redis.n8n.svc.cluster.local"
  - name: QUEUE_BULL_REDIS_PORT
    value: "6379"
```

### Enable HTTPS

Update ingress annotations in `manifests/ingress.yaml`:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
  traefik.ingress.kubernetes.io/router.tls: "true"
  cert-manager.io/cluster-issuer: letsencrypt-prod
```

And add TLS configuration:

```yaml
spec:
  tls:
    - hosts:
        - n8n.duytran.app
      secretName: n8n-tls
```

## Documentation

- [n8n Official Documentation](https://docs.n8n.io/)
- [n8n Docker Hub](https://hub.docker.com/r/n8nio/n8n)
- [n8n GitHub](https://github.com/n8n-io/n8n)
- [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)

## Why Not Helm?

n8n does not provide an official Helm chart. While community charts exist (8gears, community-charts), we prefer using official Docker images with plain Kubernetes manifests to:

- Maintain full control over configuration
- Avoid dependency on third-party chart maintenance
- Follow GitOps best practices with transparent, auditable configs
- Stay aligned with official n8n deployment recommendations
