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

Default login: `admin` / `admin`

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
