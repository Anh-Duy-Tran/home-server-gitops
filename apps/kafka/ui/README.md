# Kafka UI - Web Interface for Apache Kafka

Kafka UI is a free, open-source web interface for monitoring and managing Apache Kafka clusters. Built by Provectus and maintained by the open-source community.

## Overview

This deployment uses the **official Kafka UI Helm chart** from Provectus. It provides a lightweight, intuitive dashboard for Kafka cluster operations.

## Features

- **Multi-cluster management** - Monitor multiple Kafka clusters in one interface
- **Topic management** - Create, configure, and delete topics
- **Message browsing** - View messages with JSON, Avro, and plain text support
- **Consumer group monitoring** - Track consumer lag and offsets
- **Schema registry support** - Manage Avro, JSON Schema, and Protobuf schemas
- **Broker metrics** - Real-time performance monitoring
- **Security** - OAuth 2.0, LDAP, and RBAC support
- **Data masking** - Protect sensitive information

## Configuration

### Key Settings

- **Namespace**: `kafka` (same as Kafka cluster)
- **Image**: `provectuslabs/kafka-ui:v0.7.2`
- **Port**: 8080
- **Ingress**: Enabled with Traefik at `kafka-ui.duytran.app`

### Kafka Connection

- **Bootstrap servers**: `kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092`
- **Cluster name**: `kafka-cluster`
- **Metrics**: JMX on port 9404

### Resource Limits

- CPU: 100m request / 500m limit
- Memory: 256Mi request / 512Mi limit

## Deployment

Deploy Kafka UI via ArgoCD:

```bash
kubectl apply -f apps/kafka-ui/app.yaml
```

**Important**: Kafka UI deploys after the Kafka cluster (sync-wave: 2), so ensure Kafka is running first:

```bash
# Check Kafka cluster is ready
kubectl get kafka -n kafka
kubectl get pods -n kafka

# Then deploy UI
kubectl apply -f apps/kafka-ui/app.yaml
```

Check deployment status:

```bash
# Check pod
kubectl get pods -n kafka -l app.kubernetes.io/name=kafka-ui

# Check logs
kubectl logs -n kafka deployment/kafka-ui -f
```

## Access

### Local Access (Port Forward)

```bash
kubectl port-forward -n kafka svc/kafka-ui 8080:80
```

Then open http://localhost:8080

### Ingress Access

If DNS is configured for `kafka-ui.duytran.app`, access via:
- http://kafka-ui.duytran.app

## Usage

### Viewing Topics

1. Navigate to **Topics** in the left menu
2. Click on a topic to view details
3. Use the **Messages** tab to browse messages
4. Filter by partition, offset, or timestamp

### Creating Topics

1. Click **Topics** → **Add Topic**
2. Configure:
   - Topic name
   - Number of partitions
   - Replication factor
   - Retention settings
   - Compression type
3. Click **Create**

### Managing Consumer Groups

1. Navigate to **Consumers**
2. View all consumer groups and their lag
3. Click a group to see per-partition offsets
4. Reset offsets if needed

### Viewing Broker Metrics

1. Navigate to **Brokers**
2. View cluster health and broker list
3. Click a broker to see:
   - CPU and memory usage
   - Network throughput
   - Partition leadership

## Authentication

By default, authentication is disabled. To enable OAuth or LDAP, update `app.yaml`:

### OAuth 2.0 (GitHub Example)

```yaml
yamlApplicationConfig:
  auth:
    type: oauth2
    oauth2:
      client:
        github:
          provider: github
          clientId: your-client-id
          clientSecret: your-client-secret
          scope: read:user
          user-name-attribute: login
```

### LDAP

```yaml
yamlApplicationConfig:
  auth:
    type: ldap
    ldap:
      urls: ldap://ldap.example.com:389
      base: dc=example,dc=com
      user-dn-pattern: uid={0},ou=users
```

## RBAC (Role-Based Access Control)

Enable granular permissions:

```yaml
yamlApplicationConfig:
  rbac:
    roles:
      - name: viewer
        clusters:
          - kafka-cluster:
              - VIEW_TOPIC
              - VIEW_CONSUMER
      - name: admin
        clusters:
          - kafka-cluster:
              - VIEW_TOPIC
              - CREATE_TOPIC
              - DELETE_TOPIC
              - EDIT_TOPIC
              - VIEW_CONSUMER
              - EDIT_CONSUMER
```

## Adding Multiple Clusters

Update the `clusters` section in `app.yaml`:

```yaml
yamlApplicationConfig:
  kafka:
    clusters:
      - name: kafka-cluster
        bootstrapServers: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
      - name: another-cluster
        bootstrapServers: another-kafka:9092
        properties:
          security.protocol: SASL_SSL
          sasl.mechanism: PLAIN
          sasl.jaas.config: org.apache.kafka.common.security.plain.PlainLoginModule required username="user" password="pass";
```

## Schema Registry Integration

If you have a Schema Registry:

```yaml
yamlApplicationConfig:
  kafka:
    clusters:
      - name: kafka-cluster
        bootstrapServers: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
        schemaRegistry: http://schema-registry:8081
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n kafka -l app.kubernetes.io/name=kafka-ui
kubectl describe pod -n kafka <pod-name>
```

### View Logs

```bash
kubectl logs -n kafka deployment/kafka-ui --tail=100 -f
```

### Common Issues

1. **Cannot connect to Kafka**: Verify bootstrap servers
   ```bash
   kubectl get svc -n kafka kafka-cluster-kafka-bootstrap
   ```

2. **UI not loading**: Check ingress configuration
   ```bash
   kubectl get ingress -n kafka
   ```

3. **No metrics showing**: Ensure JMX exporter is enabled on Kafka brokers

4. **Authentication errors**: Check LDAP/OAuth configuration and secrets

## Upgrading

Update the version in `app.yaml`:

```yaml
source:
  targetRevision: 0.7.7  # New Helm chart version
  helm:
    values: |
      image:
        tag: v0.7.3  # New Docker image version
```

Then commit and push - ArgoCD will auto-sync.

## Security Recommendations

For production:

1. **Enable authentication**: Use OAuth 2.0 or LDAP
2. **Configure RBAC**: Limit user permissions appropriately
3. **Enable TLS**: Use HTTPS for ingress
4. **Data masking**: Mask sensitive fields in messages
5. **Network policies**: Restrict pod-to-pod communication

## Configuration Examples

### Data Masking

Mask sensitive fields in topic messages:

```yaml
yamlApplicationConfig:
  kafka:
    clusters:
      - name: kafka-cluster
        bootstrapServers: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
        masking:
          - type: REPLACE
            fields:
              - password
              - creditCard
            replacement: "***MASKED***"
```

### Custom Serialization

Handle custom message formats:

```yaml
yamlApplicationConfig:
  kafka:
    clusters:
      - name: kafka-cluster
        bootstrapServers: kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
        serde:
          - name: CustomAvro
            className: com.example.CustomAvroDeserializer
            filePath: /app/libs/custom-serde.jar
```

## Monitoring

Kafka UI itself exposes metrics at `/actuator/prometheus`. Add to your Prometheus scrape config:

```yaml
- job_name: kafka-ui
  kubernetes_sd_configs:
    - role: pod
      namespaces:
        names:
          - kafka
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
      action: keep
      regex: kafka-ui
```

## Documentation

- [Kafka UI GitHub](https://github.com/provectus/kafka-ui)
- [Kafka UI Documentation](https://docs.kafka-ui.provectus.io/)
- [Helm Chart Repository](https://github.com/provectus/kafka-ui-charts)
- [Docker Hub](https://hub.docker.com/r/provectuslabs/kafka-ui)

## Why Kafka UI?

Kafka UI by Provectus is the recommended web interface for Kafka because:
- **Official Helm chart**: Easy deployment and maintenance
- **Open source**: Apache 2.0 license, free forever
- **Active community**: 11.5k+ GitHub stars, 175+ contributors
- **Feature-rich**: Comprehensive management and monitoring
- **Lightweight**: Minimal resource footprint
- **Modern UI**: React-based, responsive interface
- **Production-ready**: Used by many organizations worldwide
