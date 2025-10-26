# Prefect Orchestration Server

Prefect server for workflow orchestration and scheduling.

## Components

### Prefect Server
- **Version**: 3-python3.11 (latest Prefect 3.x)
- **Port**: 4200 (API + UI)
- **Database**: SQLite on 5Gi PVC (`/var/lib/prefect/prefect.db`)
- **Resources**: 256Mi-512Mi RAM, 250m-500m CPU

## Architecture

```
Prefect Server (4200)
    ↓
SQLite DB (PVC)
```

## Access

```bash
# Port-forward to access UI
kubectl port-forward -n prefect svc/prefect-server 4200:4200

# Open browser
open http://localhost:4200
```

## API Endpoint

Internal cluster endpoint: `http://prefect-server.prefect:4200/api`

## Usage

### Configure Prefect CLI

```bash
# Set API URL
prefect config set PREFECT_API_URL=http://localhost:4200/api

# Verify connection
prefect server database status
```

## Resources

- [Prefect Documentation](https://docs.prefect.io/)
- [Prefect Kubernetes Integration](https://docs.prefect.io/integrations/prefect-kubernetes)
- [Prefect Helm Charts](https://github.com/PrefectHQ/prefect-helm)
