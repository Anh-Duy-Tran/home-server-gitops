# MLOps: Real-Time Anomaly Detection System

## 🎯 Objective

Build an MLOps pipeline that:
1. Collects real-time metrics from applications running on the cluster
2. Trains anomaly detection models (SSA/SSR-based)
3. Runs real-time inference to detect anomalies
4. Alerts on detected anomalies

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    K8s Cluster (DigitalOcean)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐                                                │
│  │ Applications │ ──── metrics ──┐                              │
│  │ (pods/svcs) │                 │                              │
│  └──────────────┘                 │                              │
│                                   ▼                              │
│  ┌────────────────────────────────────────┐                     │
│  │         Metrics Collection              │                     │
│  │  ┌──────────────┐  ┌────────────────┐ │                     │
│  │  │  Prometheus  │  │ OpenTelemetry  │ │                     │
│  │  │   (metrics)  │  │   (traces)     │ │                     │
│  │  └──────────────┘  └────────────────┘ │                     │
│  └────────────────────────────────────────┘                     │
│           │                                                      │
│           ├──── store ────► MinIO (historical data)             │
│           │                                                      │
│           └──── stream ───► Ray Serve (real-time inference)     │
│                                     │                            │
│  ┌─────────────────────────────────┴──────────────────┐        │
│  │              Ray Cluster                             │        │
│  │  ┌──────────────────┐  ┌──────────────────────┐   │        │
│  │  │  Training Jobs   │  │   Ray Serve          │   │        │
│  │  │  (Ray Tune)      │  │   (Inference API)    │   │        │
│  │  │                  │  │   - Load model       │   │        │
│  │  │  - Fetch data    │  │   - Real-time pred   │   │        │
│  │  │  - Train SSA     │  │   - Anomaly score    │   │        │
│  │  │  - Save to MinIO │  │                      │   │        │
│  │  └──────────────────┘  └──────────────────────┘   │        │
│  └──────────────────────────────────────────────────┘        │
│                              │                                  │
│                              ▼                                  │
│  ┌────────────────────────────────────────┐                   │
│  │        Alerting & Visualization         │                   │
│  │  ┌──────────────┐  ┌────────────────┐ │                   │
│  │  │  AlertManager│  │    Grafana     │ │                   │
│  │  │  (alerts)    │  │  (dashboard)   │ │                   │
│  │  └──────────────┘  └────────────────┘ │                   │
│  └────────────────────────────────────────┘                   │
│                                                                 │
│  ┌────────────────────────────────────────┐                   │
│  │          Development                    │                   │
│  │  ┌──────────────────────────────────┐  │                   │
│  │  │  Jupyter (local or cluster)      │  │                   │
│  │  │  - Experiment with models        │  │                   │
│  │  │  - Analyze metrics data          │  │                   │
│  │  │  - Test inference                │  │                   │
│  │  └──────────────────────────────────┘  │                   │
│  └────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 Phase 1: Metrics Collection

### Install Prometheus + Grafana Stack

**Using kube-prometheus-stack Helm chart:**

```yaml
# Add to k8s/k0sctl.yaml
- name: prometheus
  order: 2
  chartname: prometheus-community/kube-prometheus-stack
  version: 56.0.0
  namespace: monitoring
  values: |
    prometheus:
      prometheusSpec:
        retention: 15d
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi
              storageClassName: openebs-hostpath

        # Remote write to MinIO (via Thanos or VictoriaMetrics)
        remoteWrite:
          - url: http://victoria-metrics.monitoring:8428/api/v1/write

    grafana:
      enabled: true
      ingress:
        enabled: true
        hosts:
          - grafana.duytran.app

    alertmanager:
      enabled: true
```

### Metrics to Collect

**Application metrics:**
- Request rate (requests/sec)
- Response time (p50, p95, p99)
- Error rate (%)
- CPU usage (%)
- Memory usage (MB)
- Network I/O (bytes/sec)

**K8s metrics:**
- Pod restarts
- Container states
- Resource utilization

---

## 📦 Phase 2: Data Storage & Pipeline

### Historical Data Storage (MinIO)

```python
# Store Prometheus metrics snapshots to MinIO for training

from prometheus_api_client import PrometheusConnect
from minio import Minio
import pandas as pd
from datetime import datetime, timedelta

# Fetch metrics from Prometheus
prom = PrometheusConnect(url="http://prometheus.monitoring:9090")

# Example: Get last 7 days of CPU metrics
query = 'rate(container_cpu_usage_seconds_total[5m])'
start = datetime.now() - timedelta(days=7)
end = datetime.now()
step = '1m'

data = prom.custom_query_range(query, start, end, step)

# Convert to DataFrame
df = pd.DataFrame(data)

# Save to MinIO
minio_client = Minio(
    "minio.minio:9000",
    access_key="minioadmin",
    secret_key="minioadmin123",
    secure=False
)

# Upload as parquet for efficient storage
df.to_parquet('/tmp/metrics.parquet')
minio_client.fput_object(
    'metrics-data',
    f'raw/{datetime.now().strftime("%Y%m%d")}/cpu_metrics.parquet',
    '/tmp/metrics.parquet'
)
```

### Streaming Pipeline (Optional - for real-time)

**Option A: Prometheus Remote Write → VictoriaMetrics**
- VictoriaMetrics acts as long-term storage
- Provides PromQL interface
- More efficient than Prometheus for large datasets

**Option B: Prometheus → Kafka → Ray**
- Real-time streaming
- More complex but more flexible
- Good if you need sub-second detection

**Recommendation for MVP:** Use Option A (simpler)

---

## 🧠 Phase 3: Model Training (SSA-based Anomaly Detection)

### SSA (Singular Spectrum Analysis) Overview

**What it does:**
- Decomposes time series into trend, seasonality, and noise
- Detects anomalies by reconstruction error
- Good for cyclic patterns (daily/weekly)

### Training Pipeline with Ray

Create: `apps/mlops/training/train_ssa_model.py`

```python
import ray
from ray import train
from ray.train import RunConfig, ScalingConfig
import numpy as np
import pandas as pd
from pyssa import SSA
import tempfile
import os
from minio import Minio

def fetch_training_data():
    """Fetch metrics from MinIO"""
    minio_client = Minio(
        "minio.minio:9000",
        access_key="minioadmin",
        secret_key="minioadmin123",
        secure=False
    )

    # Download all parquet files
    objects = minio_client.list_objects('metrics-data', prefix='raw/', recursive=True)

    dfs = []
    for obj in objects:
        minio_client.fget_object('metrics-data', obj.object_name, '/tmp/temp.parquet')
        df = pd.read_parquet('/tmp/temp.parquet')
        dfs.append(df)

    return pd.concat(dfs)

def train_ssa_model(config):
    """Train SSA model for anomaly detection"""
    from ray import train
    from ray.train import Checkpoint
    import pickle

    # Load data
    df = fetch_training_data()

    # Prepare time series (example: CPU usage)
    ts = df['cpu_usage'].values

    # SSA parameters
    window_size = config.get('window_size', 50)
    n_components = config.get('n_components', 10)

    # Train SSA
    ssa = SSA(ts, window_size=window_size)
    ssa.decompose(n_components)

    # Calculate reconstruction error threshold
    reconstructed = ssa.reconstruct(0, n_components-1)
    errors = np.abs(ts - reconstructed)
    threshold = np.percentile(errors, config.get('threshold_percentile', 99))

    # Save model
    model_data = {
        'ssa': ssa,
        'window_size': window_size,
        'n_components': n_components,
        'threshold': threshold,
        'metadata': {
            'training_samples': len(ts),
            'threshold_percentile': config.get('threshold_percentile', 99)
        }
    }

    # Save to checkpoint
    tmpdir = tempfile.mkdtemp()
    model_path = os.path.join(tmpdir, 'ssa_model.pkl')
    with open(model_path, 'wb') as f:
        pickle.dump(model_data, f)

    # Report metrics
    checkpoint = Checkpoint.from_directory(tmpdir)
    train.report(
        {
            'reconstruction_error_mean': float(np.mean(errors)),
            'reconstruction_error_std': float(np.std(errors)),
            'threshold': float(threshold)
        },
        checkpoint=checkpoint
    )

# Run training with Ray
ray.init("ray://localhost:10001")  # Connect to cluster

import pyarrow.fs
s3_fs = pyarrow.fs.S3FileSystem(
    endpoint_override="localhost:9000",
    scheme="http",
    access_key="minioadmin",
    secret_key="minioadmin123",
    allow_bucket_creation=True
)

from ray.train import ScalingConfig, RunConfig

trainer = ray.train.DataParallelTrainer(
    train_ssa_model,
    train_loop_config={
        'window_size': 50,
        'n_components': 10,
        'threshold_percentile': 99
    },
    scaling_config=ScalingConfig(
        num_workers=2,
        use_gpu=False
    ),
    run_config=RunConfig(
        storage_path="mlops-models",
        storage_filesystem=s3_fs,
        name="ssa-anomaly-detection"
    )
)

result = trainer.fit()
print(f"Model saved to: {result.checkpoint}")
```

### Scheduled Retraining

Create a Kubernetes CronJob:

```yaml
# apps/mlops/manifests/training-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ssa-model-training
  namespace: mlops
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: trainer
            image: rayproject/ray:2.50.1-py311
            command: ["/bin/bash", "-c"]
            args:
              - |
                pip install pyssa prometheus-api-client minio
                python /app/train_ssa_model.py
            env:
              - name: RAY_ADDRESS
                value: "ray://raycluster-sample-head-svc.ray-system:10001"
            volumeMounts:
              - name: training-scripts
                mountPath: /app
          volumes:
            - name: training-scripts
              configMap:
                name: training-scripts
          restartPolicy: OnFailure
```

---

## 🚀 Phase 4: Real-Time Inference (Ray Serve)

### Anomaly Detection Service

Create: `apps/mlops/serving/anomaly_detector.py`

```python
import ray
from ray import serve
from fastapi import FastAPI
from pydantic import BaseModel
import pickle
import numpy as np
from minio import Minio
from typing import List
import tempfile

app = FastAPI()

class MetricsInput(BaseModel):
    metric_name: str
    values: List[float]
    timestamps: List[int]

class AnomalyResponse(BaseModel):
    is_anomaly: bool
    anomaly_score: float
    threshold: float
    detected_at: List[int]

@serve.deployment(num_replicas=2)
@serve.ingress(app)
class AnomalyDetector:
    def __init__(self, model_bucket: str, model_key: str):
        """Load SSA model from MinIO"""
        minio_client = Minio(
            "minio.minio:9000",
            access_key="minioadmin",
            secret_key="minioadmin123",
            secure=False
        )

        # Download model
        model_path = tempfile.mktemp(suffix='.pkl')
        minio_client.fget_object(model_bucket, model_key, model_path)

        # Load model
        with open(model_path, 'rb') as f:
            model_data = pickle.load(f)

        self.ssa = model_data['ssa']
        self.window_size = model_data['window_size']
        self.n_components = model_data['n_components']
        self.threshold = model_data['threshold']

    @app.post("/detect", response_model=AnomalyResponse)
    async def detect(self, data: MetricsInput):
        """Detect anomalies in incoming metrics"""
        values = np.array(data.values)

        # Reconstruct using SSA
        reconstructed = self._reconstruct(values)

        # Calculate reconstruction error
        errors = np.abs(values - reconstructed)

        # Detect anomalies (error > threshold)
        anomalies = errors > self.threshold
        anomaly_indices = np.where(anomalies)[0]

        return AnomalyResponse(
            is_anomaly=bool(np.any(anomalies)),
            anomaly_score=float(np.max(errors)),
            threshold=float(self.threshold),
            detected_at=[int(data.timestamps[i]) for i in anomaly_indices]
        )

    def _reconstruct(self, values):
        """Reconstruct time series using SSA"""
        # Apply SSA transformation
        # This is simplified - implement full SSA reconstruction
        return self.ssa.reconstruct(0, self.n_components-1)[-len(values):]

# Deploy
handle = serve.run(
    AnomalyDetector.bind(
        model_bucket="mlops-models",
        model_key="ssa-anomaly-detection/latest/ssa_model.pkl"
    ),
    route_prefix="/anomaly-detection"
)
```

### Deploy to Cluster

```yaml
# apps/mlops/manifests/anomaly-detector-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: anomaly-detector-code
  namespace: mlops
data:
  anomaly_detector.py: |
    # [paste the anomaly_detector.py code here]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anomaly-detector
  namespace: mlops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: anomaly-detector
  template:
    metadata:
      labels:
        app: anomaly-detector
    spec:
      containers:
      - name: serve
        image: rayproject/ray:2.50.1-py311
        command: ["/bin/bash", "-c"]
        args:
          - |
            pip install pyssa minio fastapi
            python /app/anomaly_detector.py
        env:
          - name: RAY_ADDRESS
            value: "ray://raycluster-sample-head-svc.ray-system:10001"
        volumeMounts:
          - name: code
            mountPath: /app
        ports:
          - containerPort: 8000
            name: http
      volumes:
        - name: code
          configMap:
            name: anomaly-detector-code
---
apiVersion: v1
kind: Service
metadata:
  name: anomaly-detector
  namespace: mlops
spec:
  selector:
    app: anomaly-detector
  ports:
    - port: 8000
      targetPort: 8000
```

---

## 🔔 Phase 5: Alerting & Monitoring

### Prometheus → Anomaly Detector → AlertManager

**Create a sidecar that queries Prometheus and calls anomaly detector:**

```python
# apps/mlops/collectors/metrics_collector.py
import time
import requests
from prometheus_api_client import PrometheusConnect

prom = PrometheusConnect(url="http://prometheus.monitoring:9090")
detector_url = "http://anomaly-detector.mlops:8000/anomaly-detection/detect"

while True:
    # Fetch latest metrics
    query = 'rate(container_cpu_usage_seconds_total{namespace="production"}[5m])'
    result = prom.custom_query(query)

    for metric in result:
        # Extract time series
        values = [float(v[1]) for v in metric['values']]
        timestamps = [int(v[0]) for v in metric['values']]

        # Call anomaly detector
        response = requests.post(detector_url, json={
            'metric_name': metric['metric']['__name__'],
            'values': values,
            'timestamps': timestamps
        })

        data = response.json()

        if data['is_anomaly']:
            # Send alert to AlertManager
            alert = {
                'labels': {
                    'alertname': 'MetricAnomaly',
                    'severity': 'warning',
                    'metric': metric['metric']['__name__'],
                    'namespace': metric['metric']['namespace']
                },
                'annotations': {
                    'summary': f"Anomaly detected in {metric['metric']['__name__']}",
                    'description': f"Anomaly score: {data['anomaly_score']:.2f}, threshold: {data['threshold']:.2f}"
                }
            }

            requests.post('http://alertmanager.monitoring:9093/api/v1/alerts', json=[alert])

    time.sleep(60)  # Check every minute
```

### Grafana Dashboard

Create dashboard showing:
- Metric values over time
- Reconstruction error
- Anomaly detections (marked as red regions)
- Anomaly score timeline

---

## 🗂️ Project Structure

```
PersonalCloud/
├── apps/
│   └── mlops/
│       ├── training/
│       │   ├── train_ssa_model.py
│       │   └── requirements.txt
│       ├── serving/
│       │   ├── anomaly_detector.py
│       │   └── requirements.txt
│       ├── collectors/
│       │   ├── metrics_collector.py
│       │   └── requirements.txt
│       ├── manifests/
│       │   ├── namespace.yaml
│       │   ├── training-cronjob.yaml
│       │   ├── anomaly-detector-deployment.yaml
│       │   ├── metrics-collector-deployment.yaml
│       │   └── ingress.yaml
│       └── mlops.argoproj.yaml
├── apps/ray/notebooks/
│   └── 02_anomaly_detection_experiments.ipynb
└── docs/
    └── MLOPS_ANOMALY_DETECTION_DESIGN.md
```

---

## 🎯 Implementation Roadmap

### Week 1: Infrastructure
- [ ] Install Prometheus + Grafana stack
- [ ] Configure metrics collection from apps
- [ ] Setup MinIO bucket for metrics data
- [ ] Create initial data export pipeline

### Week 2: Model Development
- [ ] Experiment with SSA in Jupyter
- [ ] Create training pipeline script
- [ ] Test training on Ray cluster
- [ ] Save first model to MinIO

### Week 3: Inference Service
- [ ] Build Ray Serve anomaly detector
- [ ] Deploy to cluster
- [ ] Test API endpoints
- [ ] Create metrics collector sidecar

### Week 4: Integration & Monitoring
- [ ] Connect Prometheus → Detector → AlertManager
- [ ] Build Grafana dashboards
- [ ] Setup scheduled retraining
- [ ] Documentation & handoff

---

## 💡 Future Enhancements

1. **Multiple models per metric type**
   - CPU → SSA model
   - Memory → LSTM autoencoder
   - Network → Statistical model

2. **Model versioning & A/B testing**
   - Deploy multiple model versions
   - Compare performance
   - Gradual rollout

3. **Explainability**
   - SHAP values for anomaly scores
   - Feature importance
   - Root cause analysis

4. **Feedback loop**
   - Label anomalies as true/false positives
   - Retrain with labels
   - Improve precision over time

5. **Advanced streaming**
   - Add Kafka for real-time streaming
   - Sub-second detection latency
   - Complex event processing

---

## 📚 Key Technologies

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Metrics Collection | Prometheus | Scrape metrics from apps |
| Storage | MinIO (S3) | Store historical metrics |
| Model Training | Ray Train + PySSA | Train SSA models |
| Model Serving | Ray Serve | Real-time inference API |
| Alerting | AlertManager | Send notifications |
| Visualization | Grafana | Dashboards |
| Orchestration | ArgoCD | GitOps deployment |
| Scheduling | K8s CronJob | Periodic retraining |

---

## 🔗 References

- [SSA (PySSA)](https://github.com/kieferk/pyssa)
- [Ray Train](https://docs.ray.io/en/latest/train/train.html)
- [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
- [Prometheus API Client](https://github.com/4n4nd/prometheus-api-client-python)
- [Anomaly Detection Review](https://github.com/yzhao062/anomaly-detection-resources)
