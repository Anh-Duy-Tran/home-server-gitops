# PostgreSQL Database

PostgreSQL 16 database deployed via ArgoCD with persistent storage.

## Components

- **PostgreSQL 16 (Alpine)**: Lightweight, production-ready database
- **Persistent Storage**: 10Gi PVC for data persistence
- **Namespace**: `postgres`

## Configuration

### Default Settings

- **Database**: `postgres`
- **User**: `postgres`
- **Password**: `postgres123` (⚠️ Change in production!)
- **Port**: 5432
- **Storage**: 10Gi

### Resources

- **Requests**: 256Mi memory, 250m CPU
- **Limits**: 1Gi memory, 1000m CPU

## Deployment

### Deploy via ArgoCD

```bash
kubectl apply -f apps/postgres/app.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n postgres

# Check service
kubectl get svc -n postgres

# Check PVC
kubectl get pvc -n postgres
```

## Access

### Port Forward (Local Access)

```bash
kubectl port-forward -n postgres svc/postgres 5432:5432
```

Then connect using:
```bash
psql -h localhost -U postgres -d postgres
# Password: postgres123
```

### In-Cluster Connection

From other pods in the cluster:
```
Host: postgres.postgres.svc.cluster.local
Port: 5432
User: postgres
Password: postgres123
Database: postgres
```

Connection string:
```
postgresql://postgres:postgres123@postgres.postgres.svc.cluster.local:5432/postgres
```

## Security Notes

⚠️ **IMPORTANT**: Change the default password in production!

Edit `apps/postgres/manifests/postgres-deployment.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
stringData:
  POSTGRES_PASSWORD: "your-secure-password-here"
```

## Backup & Recovery

### Create Backup

```bash
kubectl exec -n postgres deployment/postgres -- \
  pg_dump -U postgres postgres > backup.sql
```

### Restore from Backup

```bash
cat backup.sql | kubectl exec -i -n postgres deployment/postgres -- \
  psql -U postgres postgres
```

## Monitoring

Health checks are configured:
- **Liveness Probe**: `pg_isready` every 10s (after 30s delay)
- **Readiness Probe**: `pg_isready` every 5s (after 5s delay)

## Troubleshooting

### Check Logs

```bash
kubectl logs -n postgres deployment/postgres --tail=50 -f
```

### Database Shell

```bash
kubectl exec -it -n postgres deployment/postgres -- psql -U postgres
```

### Common Issues

1. **Pod not starting**: Check PVC is bound
   ```bash
   kubectl get pvc -n postgres
   ```

2. **Connection refused**: Verify service and pod are running
   ```bash
   kubectl get svc,pods -n postgres
   ```

3. **Permission errors**: Check volume mount permissions
   ```bash
   kubectl exec -n postgres deployment/postgres -- ls -la /var/lib/postgresql/data
   ```
