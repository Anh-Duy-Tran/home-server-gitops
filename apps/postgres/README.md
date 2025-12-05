# PostgreSQL Database with pgAdmin

PostgreSQL 16 database with pgAdmin web UI deployed via ArgoCD with persistent storage.

## Components

- **PostgreSQL 16 (Alpine)**: Lightweight, production-ready database
- **pgAdmin 4**: Web-based database management interface (pre-configured)
- **Persistent Storage**: 10Gi PVC for PostgreSQL, 2Gi for pgAdmin
- **Namespace**: `postgres`

## Configuration

### PostgreSQL Settings

- **Database**: `postgres`
- **User**: `postgres`
- **Password**: `postgres123` (⚠️ Change in production!)
- **Port**: 5432
- **Storage**: 10Gi
- **Resources**: 256Mi-1Gi memory, 250m-1000m CPU

### pgAdmin Settings

- **Email**: `admin@admin.com`
- **Password**: `admin` (⚠️ Change in production!)
- **Port**: 80
- **Storage**: 2Gi
- **Resources**: 256Mi-512Mi memory, 250m-500m CPU
- **Pre-configured Connection**: Automatically connects to PostgreSQL

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

### pgAdmin Web UI (Recommended)

```bash
kubectl port-forward -n postgres svc/pgadmin 8080:80
```

Open in browser: http://localhost:8080

**Login:**
- Email: `admin@admin.com`
- Password: `admin`

The PostgreSQL server is **pre-configured** and will appear automatically in the left sidebar as "Local PostgreSQL". Just expand it and start using it!

### PostgreSQL Direct Access (CLI)

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

⚠️ **IMPORTANT**: Change default passwords in production!

**PostgreSQL Password:**
Edit `apps/postgres/manifests/postgres-deployment.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
stringData:
  POSTGRES_PASSWORD: "your-secure-password-here"
```

**pgAdmin Password:**
Edit `apps/postgres/manifests/pgadmin-deployment.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-secret
stringData:
  PGADMIN_DEFAULT_EMAIL: "your-email@example.com"
  PGADMIN_DEFAULT_PASSWORD: "your-secure-password"
```

If you change the PostgreSQL password, also update the `pgpass` file in the `pgadmin-config` ConfigMap (line 28)

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

**PostgreSQL:**
```bash
kubectl logs -n postgres deployment/postgres --tail=50 -f
```

**pgAdmin:**
```bash
kubectl logs -n postgres deployment/pgadmin --tail=50 -f
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

4. **pgAdmin not showing server**: The server should auto-appear. If not, check logs:
   ```bash
   kubectl logs -n postgres deployment/pgadmin
   ```

5. **pgAdmin password error**: The password is saved on first login. To reset, delete the PVC:
   ```bash
   kubectl delete pvc pgadmin-pvc -n postgres
   kubectl rollout restart deployment/pgadmin -n postgres
   ```
