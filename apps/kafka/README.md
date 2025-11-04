# Apache Kafka - Distributed Streaming Platform

Apache Kafka is a distributed event streaming platform used for high-performance data pipelines, streaming analytics, and data integration.

## Overview

This deployment uses the **official Strimzi Kafka Operator** (CNCF project) with the official Helm chart. Strimzi provides a way to run Apache Kafka on Kubernetes following cloud-native best practices.

## Architecture

The deployment consists of two ArgoCD applications:

1. **Strimzi Operator** (`operator.yaml`) - Manages Kafka clusters
2. **Kafka Cluster** (`app.yaml`) - The actual Kafka cluster resources

## Configuration

### Kafka Cluster Specs

- **Namespace**: `kafka`
- **Kafka Version**: 3.9.0
- **Kafka Brokers**: 3 replicas
- **ZooKeeper**: 3 replicas
- **Storage**: 10Gi per broker, 5Gi per ZooKeeper (openebs-hostpath)

### Listeners

- **Plain** (port 9092): Internal, no TLS
- **TLS** (port 9093): Internal, with TLS encryption

### Replication Settings

- Default replication factor: 3
- Min in-sync replicas: 2
- Transaction log replication: 3

### Resource Allocations

**Kafka Brokers:**

- CPU: 100m request / 1000m limit
- Memory: 512Mi request / 2Gi limit

**ZooKeeper:**

- CPU: 100m request / 500m limit
- Memory: 256Mi request / 512Mi limit

**Entity Operators:**

- Topic Operator: 50m CPU / 128Mi memory
- User Operator: 50m CPU / 128Mi memory

## Directory Structure

```
apps/kafka/
├── operator.yaml         # Strimzi operator (Helm-based)
├── app.yaml             # Kafka cluster (manifest-based)
├── README.md            # This file
└── manifests/
    ├── kustomization.yaml
    └── kafka-cluster.yaml
```

## Deployment

### Step 1: Deploy Strimzi Operator

```bash
kubectl apply -f apps/kafka/operator.yaml
```

Wait for operator to be ready:

```bash
kubectl get pods -n kafka -w
# Wait for strimzi-cluster-operator to be Running
```

### Step 2: Deploy Kafka Cluster

```bash
kubectl apply -f apps/kafka/app.yaml
```

This will create:

- 3 Kafka broker pods
- 3 ZooKeeper pods
- Topic and User operators

Check deployment status:

```bash
# Check all pods
kubectl get pods -n kafka

# Check Kafka cluster status
kubectl get kafka -n kafka

# Check Kafka cluster details
kubectl describe kafka kafka-cluster -n kafka
```

## Access

### Internal Access (from within cluster)

**Bootstrap servers:**

- Plain: `kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`
- TLS: `kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9093`

### Testing Connection

```bash
# Run a test producer
kubectl run kafka-producer -ti --image=quay.io/strimzi/kafka:0.48.0-kafka-3.9.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092 --topic test-topic

# In another terminal, run a consumer
kubectl run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.48.0-kafka-3.9.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092 --topic test-topic --from-beginning
```

## Creating Topics

### Using Strimzi KafkaTopic CRD (Recommended)

Create a file `my-topic.yaml`:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: my-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 604800000 # 7 days
    segment.bytes: 1073741824
```

Apply it:

```bash
kubectl apply -f my-topic.yaml
```

### Using kafka-topics.sh

```bash
kubectl exec -it kafka-cluster-kafka-0 -n kafka -- bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 \
  --create \
  --topic my-topic \
  --partitions 3 \
  --replication-factor 3
```

## Managing Users

Create Kafka users with Strimzi KafkaUser CRD:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: my-user
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  authentication:
    type: tls
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: my-topic
          patternType: literal
        operations: [Read, Write, Describe]
        host: "*"
```

## Monitoring

Strimzi exposes Prometheus metrics for:

- Kafka brokers
- ZooKeeper
- Topic and User operators

### Prometheus Scrape Configs

Add to your Prometheus configuration:

```yaml
- job_name: "kafka"
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - kafka
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
      action: replace
      target_label: __metrics_path__
      regex: (.+)
    - source_labels:
        [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
      action: replace
      regex: ([^:]+)(?::\d+)?;(\d+)
      replacement: $1:$2
      target_label: __address__
```

## Upgrading

### Upgrade Kafka Version

Update `manifests/kafka-cluster.yaml`:

```yaml
spec:
  kafka:
    version: 3.10.0 # New version
```

Then commit and push. ArgoCD will handle the rolling upgrade.

### Upgrade Strimzi Operator

Update `operator.yaml`:

```yaml
source:
  targetRevision: 0.49.0 # New version
```

**Important**: Manually apply CRDs before upgrading:

```bash
kubectl apply -f https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.49.0/strimzi-crds-0.49.0.yaml
```

## Troubleshooting

### Check Operator Logs

```bash
kubectl logs -n kafka deployment/strimzi-cluster-operator -f
```

### Check Kafka Broker Logs

```bash
kubectl logs -n kafka kafka-cluster-kafka-0 -f
```

### Check ZooKeeper Logs

```bash
kubectl logs -n kafka kafka-cluster-zookeeper-0 -f
```

### Check Cluster Status

```bash
# Overall cluster status
kubectl get kafka -n kafka

# Broker details
kubectl get pods -n kafka -l strimzi.io/name=kafka-cluster-kafka

# Topics
kubectl get kafkatopic -n kafka

# Users
kubectl get kafkauser -n kafka
```

### Common Issues

1. **Pods stuck in Pending**: Check storage provisioner

   ```bash
   kubectl get pvc -n kafka
   kubectl get sc openebs-hostpath
   ```

2. **Brokers not starting**: Check resource availability

   ```bash
   kubectl describe pod kafka-cluster-kafka-0 -n kafka
   ```

3. **Topic creation fails**: Verify replication settings match cluster size

4. **Connection refused**: Ensure bootstrap service is running
   ```bash
   kubectl get svc -n kafka | grep bootstrap
   ```

## Advanced Configuration

### Enable External Access

Update `kafka-cluster.yaml` to add external listener:

```yaml
spec:
  kafka:
    listeners:
      - name: external
        port: 9094
        type: nodeport
        tls: false
```

### Enable TLS for All Listeners

```yaml
spec:
  kafka:
    listeners:
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls
```

### Configure Resource-Based Authorization

```yaml
spec:
  kafka:
    authorization:
      type: simple
```

### Enable Cruise Control (Auto-balancing)

```yaml
spec:
  cruiseControl:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

## Production Recommendations

1. **Pin Kafka version**: Don't use `:latest`, specify exact version
2. **Enable monitoring**: Integrate with Prometheus/Grafana
3. **Configure retention**: Set appropriate retention policies for topics
4. **Resource limits**: Adjust based on workload
5. **Backup**: Regularly backup ZooKeeper data
6. **Security**: Enable TLS and authentication for production
7. **Replication**: Ensure replication factor >= 3 for durability

## Documentation

- [Strimzi Documentation](https://strimzi.io/docs/)
- [Strimzi GitHub](https://github.com/strimzi/strimzi-kafka-operator)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Kafka on Kubernetes Best Practices](https://strimzi.io/blog/)

## Why Strimzi?

Strimzi is the recommended way to run Kafka on Kubernetes because:

- **Official CNCF project**: Industry-standard, well-maintained
- **Cloud-native**: Kubernetes-native CRDs for all operations
- **Operator pattern**: Automated lifecycle management
- **Production-ready**: Battle-tested in production environments
- **Official Helm chart**: Easy deployment and upgrades
- **Rich features**: Cruise Control, Kafka Connect, MirrorMaker 2.0
