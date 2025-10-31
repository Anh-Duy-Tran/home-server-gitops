# Project Memory - Home Server GitOps

Last updated: 2025-10-26

## Project Overview

GitOps-managed Kubernetes (k0s) cluster running on DigitalOcean with MLOps infrastructure for anomaly detection.

**GitHub Repo**: https://github.com/Anh-Duy-Tran/home-server-gitops.git

---

## Current Infrastructure

### Core Services (Running)

1. **Kubernetes Cluster (k0s)**
   - 5 worker nodes (DigitalOcean)
   - Networking: Calico with VXLAN mode (not IPIP - DO VPC blocks it)
   - Deployed via k0sctl

2. **ArgoCD**
   - Namespace: `argocd`
   - GitOps deployment of all apps
   - Auto-sync enabled with prune + selfHeal

3. **Ray Cluster**
   - Namespace: `ray-system`
   - Head: 1 pod, Workers: 4 pods
   - Image: `rayproject/ray:2.50.1-py311-gpu`
   - Metrics enabled on port 8080
   - KubeRay operator: v1.2.2

4. **MinIO**
   - Namespace: `minio`
   - S3-compatible storage
   - Endpoint: `minio.minio:9000`
   - Credentials: `minioadmin` / `minioadmin123`
   - Used for: Ray results, model registry, feature store

5. **Monitoring Stack** (`apps/prometheus/`)
   - Namespace: `monitoring`
   - **Prometheus**: v2.54.1, 20Gi storage, 30d retention
   - **Grafana**: v11.3.0, 5Gi storage
   - **Node Exporter**: DaemonSet on all nodes
   - **Kube-state-metrics**: v2.13.0
   - Credentials: admin/admin (stored in secret)

6. **Traefik Ingress**
   - Namespace: `traefik`
   - Exposes metrics on port 9100
   - Prometheus scraping enabled

### Applications (Running)

- `hello-world` (namespace: default)
- `visitor-counter` (namespace: stateful-apps)
- `photoBook` (namespace: default)
- `adguard` (namespace: stateful-apps)

---

## Just Completed (This Session)

### 1. Monitoring Stack Setup 

Created comprehensive observability:
- Prometheus with auto-discovery of:
  - Kubernetes nodes/pods/services
  - Ray cluster (head + workers)
  - Traefik metrics
  - Node-exporter metrics
- Grafana with 3 auto-provisioned dashboards:
  1. **Kubernetes Cluster Health** - node CPU/memory/disk/network
  2. **Ray Cluster Overview** - distributed compute metrics
  3. **Traefik Ingress Controller** - HTTP traffic, latency, errors

**Key files:**
- `apps/prometheus/manifests/` - all Prometheus/Grafana manifests
- `apps/prometheus/manifests/configs/` - Prometheus config, datasources, dashboards
- Uses Kustomize with configMapGenerator (auto-hash for immutable configs)

### 2. MLOps Architecture Design 

**Goal**: Real-time anomaly detection with specialized models

**Approach**: Multiple purpose-built models (not general anomaly detector)
- Model A: Memory Leak Detector (OOM prevention)
- Model B: DDoS Attack Detector (traffic anomalies)
- Model C: Performance Degradation Detector
- Model D: Resource Starvation Detector

**Focus**: Start with Memory Leak Detection

### 3. Separated MLOps Infrastructure 

Created 3 separate ArgoCD apps for clean architecture:

**A. Feast Feature Store** (`apps/feast/`)
- Namespace: `feast`
- Component: Redis v7 (online store for fast feature serving)
- Purpose: Online store for real-time inference
- Offline store: MinIO (configured in feature_store.yaml)
- ArgoCD app: `apps/feast/app.yaml`

**B. Prefect Orchestration** (`apps/prefect/`)
- Namespace: `prefect`
- Component: Prefect Server v2 (Python 3.11)
- Port: 4200 (API + UI)
- Database: SQLite on 5Gi PVC
- Purpose: Workflow orchestration and scheduling
- ArgoCD app: `apps/prefect/app.yaml`

**C. MLOps Workflows** (`apps/mlops/`)
- No separate namespace (uses feast + prefect namespaces)
- Will contain:
  - `flows/` - Prefect flow definitions
  - `feature_repo/` - Feast feature definitions
  - `models/` - Model code (SSA, etc.)
  - `docker/` - Flow runner images

---

## What Needs to Be Done Next

### Immediate Next Steps

1. **Deploy Feast + Prefect** =4 HIGH PRIORITY
   ```bash
   # From project root
   kubectl apply -f apps/feast/app.yaml
   kubectl apply -f apps/prefect/app.yaml

   # Verify
   kubectl get pods -n feast
   kubectl get pods -n prefect

   # Access Prefect UI
   kubectl port-forward -n prefect svc/prefect-server 4200:4200
   # Open http://localhost:4200
   ```

2. **Finish MLOps App Structure**
   - Complete `apps/mlops/` directory structure
   - Create placeholder directories:
     - `apps/mlops/flows/`
     - `apps/mlops/feature_repo/`
     - `apps/mlops/models/`
     - `apps/mlops/docker/`
   - Update `apps/mlops/README.md` with deployment instructions

3. **Verify All Apps Build**
   ```bash
   kubectl kustomize apps/feast/manifests
   kubectl kustomize apps/prefect/manifests
   ```

### Phase 2: Data Collection Pipeline

**Goal**: Collect 30 days of metrics for memory leak training data

**Data Footprint**: ~500 MB total (30 days)
- Raw metrics (1-min aggregated): 300-400 MB (Parquet compressed)
- Engineered features: 100 MB
- Labels & incidents: 10 MB
- Model artifacts: 50 MB

**Metrics to Collect** (for memory leak detection):
```
1. container_memory_working_set_bytes
2. kube_pod_container_resource_limits_memory_bytes
3. kube_pod_container_resource_requests_memory_bytes
4. kube_pod_container_status_restarts_total
5. rate(traefik_service_requests_total[1m]) - for traffic correlation
6. kube_pod_container_status_terminated_reason{reason="OOMKilled"}
```

**Feature Engineering Strategy**:
```python
# Key insight: Normal apps have memory correlated with traffic
# Memory leaks: memory grows regardless of traffic

Features to compute:
- memory_usage_pct = usage / limit
- memory_per_request = memory / (request_rate + 1)
- memory_growth_1h = delta over 1 hour
- traffic_correlation_6h = corr(memory, traffic) over 6h window
- gc_ratio_1h = % of time memory decreases (GC activity)
- retention_ratio = current / peak memory
```

**Data Labeling Strategy**:
1. **Automatic labels**:
   - `oom_event`: 4 hours before OOM kill
   - `normal`: No OOM, memory < 80%, no restarts
   - `post_restart`: Pod just restarted
2. **Heuristic labels**:
   - `suspected_leak`: Memory growth + low traffic correlation + no GC
3. **Human-in-the-loop**: Feedback table for validation

**Next Actions**:
1. Create Feast feature definitions in `apps/mlops/feature_repo/features.py`
2. Create Prefect data collection flow in `apps/mlops/flows/data_collection_flow.py`
3. Build Docker image with Prefect + dependencies
4. Deploy flow to run every 5 minutes

### Phase 3: Model Training

**Approach**: SSA (Singular Spectrum Analysis) or Isolation Forest

**Training Pipeline**:
1. Load last 7-30 days from Feast offline store (MinIO)
2. Split train/test (temporal split, not random)
3. Train model with Ray Train (distributed)
4. Validate on historical OOM incidents
5. Save to model registry (MinIO)
6. Run weekly (Sundays 2 AM)

### Phase 4: Real-time Inference

**Ray Serve Deployment**:
- Load latest features from Feast online store (Redis)
- Run inference every 15s for all pods
- Alert if memory leak probability > 0.8
- Route alerts to Slack/PagerDuty

---

## Important Technical Decisions

### 1. Networking
- **MUST use Calico VXLAN mode** (not IPIP)
- Reason: DigitalOcean VPC blocks IP protocol 4 (IPIP encapsulation)
- Config: `k8s/k0sctl.yaml` line 317

### 2. Monitoring
- **Prometheus scrape annotations**:
  - Traefik uses `prometheus.io/scrape: "true"` and `prometheus.io/port: "9100"`
  - Fixed relabeling config to use `__meta_kubernetes_pod_ip` instead of `__address__`
- **Datasource UID**: Must be `uid: prometheus` (not auto-generated) for dashboards to work
- **ConfigMaps with hash suffixes**: Kustomize `configMapGenerator` creates immutable configs

### 3. ArgoCD
- **All apps have finalizer**: `resources-finalizer.argocd.argoproj.io`
  - Ensures cascade deletion of resources
  - Prevents orphaned pods/services/PVCs

### 4. Ray
- **Metrics enabled**: `rayStartParams: metrics-export-port: "8080"`
- **Annotations for Prometheus**:
  ```yaml
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
  ```

### 5. Kustomize
- Use `labels` (not deprecated `commonLabels`)
- `configMapGenerator` for configs (creates hash suffixes)
- `namespace` field applies to all resources

---

## Architecture Diagrams

### Current State
```
                                                             
                    Applications                              
  (visitor-counter, photoBook, hello-world, etc.)            
                  ,                                          
                   
                   “
                          
              Traefik      (Ingress)
            :80, :443     
                  ,       
                   
                   “ Metrics (9100)
                          
             Prometheus    (Scrapes every 15s)
               :9090      
                  ,       
                   
                   “
                          
              Grafana      (Visualization)
               :3000      
                          

Parallel Infrastructure:
                                            
 Ray Cluster       MinIO          ArgoCD    
 (Compute)       (Storage)        (GitOps)  
                                            
```

### Target MLOps Architecture
```
Applications ’ Traefik ’ Prometheus (15s scrape)
                            “
                                   
                     Prefect Flow   (every 5 min)
                     Data Collect  
                           ,       
                            “
                    Feature Engineering
                            “
                           4             
              “                           “
    Feast Offline Store              Feast Online Store
      (MinIO - training)              (Redis - serving)
              “                           “
                                             
      Ray Train                  Ray Serve   
      (weekly train)             (inference) 
             ,                       ,       
              “                          “
      Model Registry              Predictions
       (MinIO)                         “
                                   Alerts
                              (Slack/PagerDuty)
```

---

## Key Files & Locations

### Infrastructure
- `k8s/k0sctl.yaml` - k0s cluster config (Calico VXLAN mode!)
- `apps/*/app.yaml` - ArgoCD Application manifests

### Monitoring
- `apps/prometheus/manifests/configs/prometheus.yml` - Scrape configs
- `apps/prometheus/manifests/configs/datasources.yaml` - Grafana datasource (uid: prometheus)
- `apps/prometheus/manifests/configs/dashboards/*.json` - Auto-provisioned dashboards

### MLOps (New)
- `apps/feast/` - Feature store (Redis online store)
- `apps/prefect/` - Orchestration server
- `apps/mlops/` - Workflows (flows, features, models)

### Ray
- `apps/ray/manifests/ray-cluster-sample.yaml` - Ray cluster config with metrics
- `apps/ray/notebooks/` - Local Jupyter notebooks for development
- `apps/ray/notebooks/pyproject.toml` - Python deps (uv package manager)

---

## Access Information

### Services

| Service | Namespace | Port Forward | URL |
|---------|-----------|--------------|-----|
| Grafana | monitoring | `kubectl port-forward -n monitoring svc/grafana 3000:3000` | http://localhost:3000 |
| Prometheus | monitoring | `kubectl port-forward -n monitoring svc/prometheus 9090:9090` | http://localhost:9090 |
| Prefect | prefect | `kubectl port-forward -n prefect svc/prefect-server 4200:4200` | http://localhost:4200 |
| Ray Dashboard | ray-system | `kubectl port-forward -n ray-system svc/raycluster-sample-head-svc 8265:8265` | http://localhost:8265 |
| Ray Client | ray-system | `kubectl port-forward -n ray-system svc/raycluster-sample-head-svc 10001:10001` | ray://localhost:10001 |
| MinIO | minio | `kubectl port-forward -n minio svc/minio 9000:9000` | http://localhost:9000 |
| Redis (Feast) | feast | `kubectl port-forward -n feast svc/redis 6379:6379` | localhost:6379 |

### Credentials

- **Grafana**: admin / admin (secret: `grafana-admin` in monitoring namespace)
- **MinIO**: minioadmin / minioadmin123
- **Prefect**: No auth (local deployment)

---

## Common Commands

### Deployment
```bash
# Deploy/update app via ArgoCD
kubectl apply -f apps/<app-name>/app.yaml

# Manual kustomize build (verify before deploying)
kubectl kustomize apps/<app-name>/manifests

# Check ArgoCD sync status
kubectl get application <app-name> -n argocd -o jsonpath='{.status.sync.status}'
```

### Debugging
```bash
# Check pods
kubectl get pods -n <namespace>

# Get logs
kubectl logs -n <namespace> deployment/<name> --tail=50

# Check Prometheus targets
kubectl exec -n monitoring deployment/prometheus -- \
  wget -qO- 'localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.health == "down")'

# Test metrics endpoint
kubectl exec -n <namespace> <pod-name> -- wget -qO- http://localhost:<port>/metrics
```

### Git
```bash
# Commit changes (no GPG needed)
git add .
git commit -m "message"
git push

# Check status
git status
```

---

## Known Issues & Workarounds

### 1. Node Online Widget Shows 0
**Issue**: Grafana dashboard shows 0 nodes online
**Cause**: `kubernetes-nodes` job gets 403 Forbidden from kubelet
**Solution**: Use `node-exporter` metrics instead
**Status**: Need to update dashboard query from `sum(up{job="kubernetes-nodes"})` to `sum(up{job="node-exporter"})`

### 2. ArgoCD Connection Timeouts
**Issue**: Logs show "context canceled" errors
**Cause**: Normal behavior - ArgoCD UI uses Server-Sent Events (SSE) for real-time updates
**Solution**: Ignore - not a real error, just connection resets

### 3. Ray Tasks Only on Head
**Issue**: Ray tasks not distributing to workers
**Cause**: Need explicit resource request: `@ray.remote(num_cpus=1)`
**Solution**: Always specify CPU requirements for tasks

---

## Environment Setup

### Local Development (Ray Notebooks)
```bash
cd apps/ray/notebooks

# Install uv (if not installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create venv and install deps
uv venv
source .venv/bin/activate
uv pip install -e .

# Start Jupyter
jupyter lab

# Port-forward Ray cluster
kubectl port-forward -n ray-system svc/raycluster-sample-head-svc 10001:10001 8265:8265
```

---

## Resources & Documentation

### External Docs
- [Feast Documentation](https://docs.feast.dev/)
- [Prefect Documentation](https://docs.prefect.io/)
- [Ray Documentation](https://docs.ray.io/)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Grafana Dashboard Docs](https://grafana.com/docs/grafana/latest/dashboards/)

### Project Docs
- `apps/prometheus/README.md` - Monitoring stack guide
- `apps/feast/README.md` - Feature store setup
- `apps/prefect/README.md` - Workflow orchestration
- `apps/mlops/README.md` - ML workflows (in progress)

---

## Open Questions / Decisions Needed

1. **Alerting Destination**: Slack, PagerDuty, or Grafana annotations?
2. **Model Retraining**: Daily, weekly, or on-demand (triggered by feedback)?
3. **Feature Store Schema**: Final approval on memory leak features?
4. **Alert Thresholds**: What probability threshold for memory leak alerts (0.8? 0.9?)?
5. **Kubernetes Dashboard Query**: Update to use node-exporter instead of kubernetes-nodes job?

---

## Git Workflow

**Main branch**: `main`
**Deployment**: ArgoCD watches `main` branch, auto-syncs all apps

**Current uncommitted changes** (as of last session):
- `apps/prometheus/manifests/configs/prometheus.yml` - Fixed kubernetes-pods relabeling
- `apps/feast/` - Complete new app
- `apps/prefect/` - Complete new app
- `apps/mlops/README.md` - Updated for new structure

**Next commit**:
```bash
git add apps/feast apps/prefect apps/mlops
git commit -m "Add Feast feature store and Prefect orchestration for MLOps pipeline"
git push
```

---

## Session Notes

### 2025-10-26 Session
- Set up complete monitoring stack (Prometheus + Grafana + 3 dashboards)
- Designed MLOps architecture for memory leak detection
- Created separate Feast and Prefect apps for clean architecture
- Calculated 30-day data footprint (~500MB)
- Defined feature engineering strategy for memory leak detection
- Fixed Prometheus scraping for Traefik metrics
- Added Grafana datasource UID to fix dashboard issues

**Status at end of session**:
-  Monitoring infrastructure