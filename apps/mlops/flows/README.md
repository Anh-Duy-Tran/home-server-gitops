# Prefect Flows

ETL workflows for MLOps pipeline.

## Flows

### data_collection_flow.py
Collects metrics from Prometheus every 5 minutes for memory leak detection.

**What it does:**
1. Queries Prometheus for memory metrics (usage, limits, OOM kills, etc.)
2. Transforms and aggregates data
3. Writes to MinIO as Parquet files

**Schedule:** Every 5 minutes

## Local Development

### Setup
```bash
cd apps/mlops/flows

# Install dependencies
pip install -r requirements.txt

# Configure Prefect to use cluster
kubectl port-forward -n prefect svc/prefect-server 4200:4200
prefect config set PREFECT_API_URL=http://localhost:4200/api
```

### Test Flow Locally
```bash
# Port-forward Prometheus and MinIO
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n minio svc/minio 9000:9000

# Run flow
python data_collection_flow.py
```

## Deploy to Prefect

### Option 1: Deploy from local machine
```bash
# Deploy the flow
prefect deploy data_collection_flow.py:data_collection_flow \
  --name "data-collection" \
  --pool "kubernetes" \
  --cron "*/5 * * * *"
```

### Option 2: Build and push Docker image
```bash
# TODO: Create Dockerfile and push to registry
```

## Monitoring

Access Prefect UI:
```bash
kubectl port-forward -n prefect svc/prefect-server 4200:4200
open http://localhost:4200
```

## Data Output

**Location:** `s3://metrics/memory_metrics/`
**Format:** Parquet (Snappy compressed)
**Naming:** `YYYYMMDD_HHMMSS.parquet`

Each file contains ~5 minutes of metrics at 1-minute resolution.
