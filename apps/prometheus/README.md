# Prometheus Monitoring Stack

This directory contains the Prometheus and Grafana monitoring stack for the Kubernetes cluster.

## Components

### Prometheus
- **Version**: v2.54.1
- **Storage**: 20Gi persistent volume
- **Retention**: 30 days
- **Port**: 9090

### Grafana
- **Version**: v11.3.0
- **Storage**: 5Gi persistent volume
- **Port**: 3000
- **Default credentials**: admin/admin (change after first login)

### Node Exporter (DaemonSet)
- **Version**: v1.8.2
- Runs on every node to collect hardware and OS metrics
- **Metrics**: CPU, memory, disk, network, filesystem

### Kube State Metrics
- **Version**: v2.13.0
- Exposes Kubernetes object state metrics
- **Metrics**: Pods, deployments, nodes, namespaces, etc.

## Metrics Collection

The Prometheus configuration automatically scrapes metrics from:

1. **Kubernetes API Server** - Cluster-level metrics
2. **Kubernetes Nodes** - Node resource metrics
3. **Kubernetes Pods** - Pod-level metrics (requires `prometheus.io/scrape: "true"` annotation)
4. **Ray Cluster Head** - Ray head node metrics on port 8080
5. **Ray Workers** - Ray worker node metrics on port 8080

## Accessing the UIs

### Prometheus UI

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then open http://localhost:9090

### Grafana UI

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Then open http://localhost:3000

**Default credentials:**
- Username: `admin`
- Password: `admin`

**⚠️ Important:** Change the admin password after first login!

To change the password:
1. Update `secretGenerator` in `manifests/kustomization.yaml`
2. Change the `admin-password` value
3. Commit and push - ArgoCD will update the secret

## Pre-configured Dashboards

Grafana comes with pre-configured dashboards:

### 1. Kubernetes Cluster Health

Shows k0s cluster infrastructure metrics:

- **Overview Stats**: Nodes online, running pods, namespaces, unhealthy pods
- **Resource Gauges**: Cluster-wide CPU and memory usage
- **Node Metrics**: Per-node CPU, memory, disk usage over time
- **Network Traffic**: RX/TX per node
- **Pod Distribution**: Pods per namespace, pod status pie chart

Access: **Dashboards → Kubernetes Cluster Health**

### 2. Ray Cluster Overview

Shows Ray distributed computing metrics:

- **CPU/Memory Usage**: Total and used resources per Ray node
- **Cluster Stats**: Total nodes, CPUs, memory, active actors
- **Task Execution**: Task completion rates and states
- **Object Store**: Memory usage in Ray's object store
- **CPU Distribution**: CPU allocation across nodes

Access: **Dashboards → Ray Cluster Overview**

### 3. Traefik Ingress Controller

Shows HTTP ingress/reverse proxy metrics:

- **Overview Stats**: Request rate, active connections, response times, config reload status
- **Request Rate**: Per entrypoint (web, websecure)
- **Status Codes**: 2xx, 4xx, 5xx distribution over time
- **Response Times**: p50, p95, p99 latency percentiles
- **Connections**: Open connections per entrypoint
- **HTTP Methods**: Request distribution (GET, POST, etc.)
- **Backends**: Request rate per service/backend

Access: **Dashboards → Traefik Ingress Controller**

### Adding Custom Dashboards

To add your own dashboards:

1. Create a JSON file in `manifests/configs/dashboards/`
2. Add it to `configMapGenerator` in `manifests/kustomization.yaml`:
   ```yaml
   - name: grafana-dashboards
     files:
       - ray-cluster.json=configs/dashboards/ray-cluster.json
       - your-dashboard.json=configs/dashboards/your-dashboard.json
   ```
3. Commit and push - Grafana will auto-load it

## Ray Metrics

The Ray cluster exposes metrics on port 8080 at the `/metrics` endpoint. Key metrics include:

- `ray_node_cpu_count` - Number of CPUs per node
- `ray_node_mem_used` - Memory usage per node
- `ray_tasks_pending` - Number of pending tasks
- `ray_tasks_running` - Number of running tasks
- `ray_actors_total` - Total number of actors
- `ray_placement_groups_total` - Total placement groups

Example Prometheus query:
```promql
rate(ray_tasks_running[5m])
```

## Adding Custom Metrics

To add custom metrics from your applications:

1. Expose metrics in Prometheus format on an HTTP endpoint
2. Add annotations to your pod template:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"      # Your metrics port
    prometheus.io/path: "/metrics"  # Your metrics path
```

3. Prometheus will automatically discover and scrape your metrics

## Deployment

This monitoring stack is deployed via ArgoCD using the `app.yaml` manifest.

To deploy manually:
```bash
kubectl apply -f app.yaml
```

To check deployment status:
```bash
kubectl get pods -n monitoring
kubectl get application prometheus -n argocd
```
