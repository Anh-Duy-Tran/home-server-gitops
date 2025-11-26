# Voice Assistant for Home Automation

Local, privacy-focused voice assistant running on Kubernetes with wake word detection, speech-to-text (Vosk), and MQTT integration with n8n and Home Assistant.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                      │
│                                                              │
│  ┌──────────────┐      ┌──────────────┐                    │
│  │ Voice Agent  │─────>│ Mosquitto    │                    │
│  │ (Vosk STT)   │ MQTT │ MQTT Broker  │                    │
│  │              │      │              │                    │
│  │ - Wake word  │      └──────┬───────┘                    │
│  │ - Record     │             │                            │
│  │ - Transcribe │             │ Topic:                     │
│  └──────────────┘             │ home/voice/commands        │
│        │                      │                            │
│        │ Audio                ▼                            │
│        │                ┌──────────────┐                   │
│  ┌─────▼──────┐        │     n8n      │                   │
│  │ USB Mic    │        │ Workflow     │                   │
│  │ (Pi Node)  │        │              │                   │
│  └────────────┘        └──────┬───────┘                   │
│                               │                            │
│                               │ HTTP API Call              │
│                               ▼                            │
│                        ┌──────────────┐                    │
│                        │    Home      │                    │
│                        │  Assistant   │                    │
│                        └──────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Mosquitto MQTT Broker
- **Namespace**: `voice-assistant`
- **Port**: 1883 (internal)
- **Storage**: 1Gi PVC for message persistence
- **Purpose**: Message broker between voice agent and n8n

### 2. Voice Agent
- **Technology**: Python 3.11 + Vosk STT + sounddevice
- **Wake Phrases**: "hey assistant", "hey wolt", "ok assistant"
- **Model**: Vosk small English model (~40MB)
- **Node Requirements**: Access to USB microphone (runs on Home Assistant Pi node)
- **Output**: JSON messages to MQTT topic `home/voice/commands`

### 3. n8n Integration
- **Trigger**: MQTT subscriber on `home/voice/commands`
- **Processing**: Parse voice commands, map to Home Assistant services
- **Action**: Call Home Assistant REST API

## Prerequisites

1. **Kubernetes cluster** with k0s (already set up)
2. **USB Microphone** plugged into one worker node (Home Assistant Pi)
3. **Docker registry** to host the voice agent image
4. **Home Assistant** running in the cluster with REST API enabled
5. **n8n** running in the cluster (already set up)
6. **API Key** (optional): For cloud STT backends (Groq or OpenRouter) - see [SECRETS_SETUP.md](SECRETS_SETUP.md)

## Setup Instructions

### Step 1: Label Your Microphone Node

First, identify which node has the USB microphone (your Home Assistant Raspberry Pi):

```bash
# List your nodes
kubectl get nodes

# Label the node with the microphone
kubectl label node <your-ha-node-name> voice-capable=true
```

Then update `manifests/voice-agent.yaml` to uncomment the `voice-capable: "true"` node selector.

### Step 2: Build and Push Voice Agent Image

```bash
cd apps/voice-assistant

# Build the Docker image
docker build -t your-registry.com/voice-agent:latest .

# Push to your registry
docker push your-registry.com/voice-agent:latest
```

Update `manifests/voice-agent.yaml` with your image path:
```yaml
image: your-registry.com/voice-agent:latest
```

### Step 3: Deploy via ArgoCD

```bash
# Deploy the ArgoCD application
kubectl apply -f app.yaml

# Check deployment status
kubectl get application voice-assistant -n argocd

# Wait for sync
kubectl wait --for=condition=Synced application/voice-assistant -n argocd --timeout=300s

# Verify pods are running
kubectl get pods -n voice-assistant
```

Expected output:
```
NAME                           READY   STATUS    RESTARTS   AGE
mosquitto-xxxxxxxxxx-xxxxx     1/1     Running   0          2m
voice-agent-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### Step 4: Configure n8n Workflow

#### 4.1 Add MQTT Credentials in n8n

1. Access n8n UI (port-forward if needed):
   ```bash
   kubectl port-forward -n n8n svc/n8n 5678:5678
   ```

2. Go to **Settings** → **Credentials** → **Add Credential**

3. Select **MQTT** and configure:
   - **Name**: Voice Assistant MQTT
   - **Protocol**: mqtt
   - **Host**: mosquitto.voice-assistant.svc.cluster.local
   - **Port**: 1883
   - **Username**: (leave empty if anonymous)
   - **Password**: (leave empty if anonymous)

#### 4.2 Add Home Assistant Credentials

1. In n8n, add **HTTP Header Auth** credential:
   - **Name**: Home Assistant Bearer Token
   - **Header Name**: Authorization
   - **Value**: `Bearer YOUR_HA_LONG_LIVED_TOKEN`

   To get a Home Assistant token:
   - Go to Home Assistant → Profile → Long-Lived Access Tokens
   - Create a new token
   - Copy and paste it with `Bearer ` prefix

#### 4.3 Import Workflow

1. In n8n, go to **Workflows** → **Import from File**
2. Upload `n8n-integration.json` from this directory
3. Update the workflow nodes:
   - **MQTT Trigger**: Select "Voice Assistant MQTT" credential
   - **Call Home Assistant**: Select "Home Assistant Bearer Token" credential
   - **Call Home Assistant**: Update URL to your HA instance (e.g., `http://homeassistant.default.svc.cluster.local:8123`)
4. **Activate** the workflow

### Step 5: Test the System

#### 5.1 Check Logs

```bash
# Voice agent logs
kubectl logs -n voice-assistant deployment/voice-agent -f

# MQTT broker logs
kubectl logs -n voice-assistant deployment/mosquitto -f
```

#### 5.2 Test Wake Word

Speak near the microphone:
```
"Hey assistant, turn on the kitchen light"
```

You should see in the logs:
```
2025-11-26 10:30:15 - Wake phrase detected: 'hey assistant'
2025-11-26 10:30:18 - Command transcribed: 'turn on the kitchen light'
2025-11-26 10:30:18 - Published command: turn on the kitchen light
```

#### 5.3 Verify MQTT Message

```bash
# Install mosquitto-clients on your local machine
brew install mosquitto  # macOS
# or: apt-get install mosquitto-clients  # Linux

# Port-forward MQTT broker
kubectl port-forward -n voice-assistant svc/mosquitto 1883:1883

# Subscribe to the topic (in another terminal)
mosquitto_sub -h localhost -t "home/voice/commands" -v
```

When you trigger a voice command, you should see JSON like:
```json
{
  "user": "duy",
  "text": "turn on the kitchen light",
  "confidence": 0.9,
  "source": "k8s-voice-assistant",
  "timestamp": "2025-11-26T10:30:18.123456"
}
```

## Configuration

### Secrets Management

API keys and sensitive data are managed separately from configuration. See the complete guide:

**📚 [SECRETS_SETUP.md](SECRETS_SETUP.md)** - Comprehensive secrets management for local and Kubernetes

Quick secret setup:
```bash
# For cloud STT (Groq or OpenRouter)
kubectl create secret generic voice-agent-secret \
  --from-literal=STT_API_KEY='your_api_key_here' \
  -n voice-assistant

# For local Vosk (no secret needed)
# Just deploy - it works without API keys
```

### Voice Agent Environment Variables

Edit `manifests/voice-agent.yaml` ConfigMap to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `MQTT_BROKER` | mosquitto.voice-assistant.svc.cluster.local | MQTT broker hostname |
| `MQTT_PORT` | 1883 | MQTT broker port |
| `MQTT_TOPIC` | home/voice/commands | Topic to publish commands |
| `SAMPLE_RATE` | 16000 | Audio sample rate (Hz) |
| `WAKE_PHRASES` | hey assistant,hey wolt,ok assistant | Comma-separated wake phrases |
| `POST_WAKE_RECORD_SECONDS` | 3.0 | Seconds to record after wake word |
| `USER` | duy | User identifier in MQTT messages |
| `SOURCE` | k8s-voice-assistant | Source identifier |

After editing, redeploy:
```bash
kubectl rollout restart deployment/voice-agent -n voice-assistant
```

### n8n Command Parsing

Edit the "Parse Voice Command" function node in n8n to add more commands:

```javascript
// Example: Add garage door control
else if (text.includes('garage')) {
  if (text.includes('open')) {
    haService = 'cover/open_cover';
    entityId = 'cover.garage_door';
  } else if (text.includes('close')) {
    haService = 'cover/close_cover';
    entityId = 'cover.garage_door';
  }
}
```

## Troubleshooting

### Voice Agent Not Starting

**Symptom**: Pod in CrashLoopBackOff

**Check**:
```bash
kubectl logs -n voice-assistant deployment/voice-agent
```

**Common Issues**:
1. **No audio device**: Voice agent needs to run on a node with a USB microphone
   - Solution: Label the correct node and update nodeSelector
2. **Vosk model download failed**: Network issues during image build
   - Solution: Rebuild the Docker image
3. **MQTT connection failed**: Mosquitto not ready
   - Solution: Check mosquitto pod is running

### Wake Word Not Detected

**Symptom**: Voice agent running but doesn't respond to wake phrases

**Debugging**:
```bash
# Check audio input levels
kubectl exec -it -n voice-assistant deployment/voice-agent -- bash
# Inside container:
python3 -c "import sounddevice as sd; print(sd.query_devices())"
```

**Solutions**:
1. **Wrong audio device**: Container may be using wrong device
   - Ensure USB mic is default or specify device index
2. **Background noise**: Vosk may not hear clearly
   - Try speaking louder or closer to microphone
3. **Wake phrase not in vocabulary**: Vosk model may not recognize the phrase
   - Try default phrases: "hey assistant", "ok assistant"

### MQTT Messages Not Reaching n8n

**Check MQTT**:
```bash
# Subscribe to all topics to see if messages are published
kubectl exec -n voice-assistant deployment/mosquitto -- \
  mosquitto_sub -h localhost -t "#" -v
```

**Check n8n**:
1. Workflow is activated (toggle on)
2. MQTT Trigger node credentials are correct
3. n8n can reach mosquitto service: `mosquitto.voice-assistant.svc.cluster.local:1883`

### Home Assistant Commands Not Executing

**Check n8n execution log**:
- Go to n8n UI → Workflows → Voice Assistant to Home Assistant → Executions
- Click on failed execution to see error details

**Common Issues**:
1. **401 Unauthorized**: Invalid Home Assistant token
   - Regenerate token in HA and update n8n credential
2. **404 Not Found**: Wrong entity ID or service name
   - Check HA entity IDs: Configuration → Entities
3. **Service call failed**: Entity doesn't support the service (e.g., can't turn on a sensor)
   - Update n8n command parsing logic

## Monitoring

### View Voice Commands

```bash
# Real-time voice agent logs
kubectl logs -n voice-assistant deployment/voice-agent -f --tail=50

# Filter for wake word detections
kubectl logs -n voice-assistant deployment/voice-agent | grep "Wake phrase detected"
```

### MQTT Statistics

```bash
# Check MQTT broker stats
kubectl exec -n voice-assistant deployment/mosquitto -- \
  mosquitto_sub -h localhost -t '$SYS/#' -v | head -20
```

### Add Prometheus Monitoring (Optional)

To monitor voice agent metrics, add Prometheus annotations to the voice-agent deployment:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## Advanced Configuration

### Add Authentication to MQTT

Edit `manifests/mqtt-broker.yaml` ConfigMap:

```yaml
data:
  mosquitto.conf: |
    listener 1883
    allow_anonymous false
    password_file /mosquitto/config/password_file
```

Create password file:
```bash
# On your local machine
mosquitto_passwd -c password_file voice_agent

# Create secret
kubectl create secret generic mosquitto-password \
  --from-file=password_file=password_file \
  -n voice-assistant

# Mount secret in mosquitto deployment
```

### Use Whisper for Better Accuracy

Replace Vosk with OpenAI Whisper for better transcription (requires more CPU/GPU):

Update `Dockerfile`:
```dockerfile
RUN pip install openai-whisper

# Download Whisper model (base, small, medium, large)
RUN whisper --model base --download-root /models
```

Update `voice_agent.py` to use Whisper instead of Vosk (implementation not included here).

### Run on GPU Node

For better performance with Whisper or larger Vosk models:

1. Label GPU node:
   ```bash
   kubectl label node <gpu-node> accelerator=nvidia-gpu
   ```

2. Update `manifests/voice-agent.yaml`:
   ```yaml
   nodeSelector:
     accelerator: nvidia-gpu
   resources:
     limits:
       nvidia.com/gpu: 1
   ```

## Security Considerations

1. **Microphone Access**: Voice agent runs with `privileged: true` to access host audio devices
   - Risk: Container has elevated privileges
   - Mitigation: Run on dedicated node, use pod security policies

2. **MQTT Anonymous Access**: Currently allows anonymous connections
   - Risk: Anyone on the network can publish/subscribe
   - Mitigation: Enable authentication (see Advanced Configuration)

3. **Home Assistant Token**: Long-lived token stored in n8n
   - Risk: Token compromise gives full HA access
   - Mitigation: Use Kubernetes secrets, rotate tokens regularly

4. **Privacy**: All audio processing is local (no cloud)
   - ✅ Audio never leaves your LAN
   - ✅ No third-party wake word services
   - ✅ No telemetry or analytics

## Performance

### Resource Usage (Measured)

| Component | CPU (avg) | Memory (avg) | Storage |
|-----------|-----------|--------------|---------|
| Voice Agent | 500m | 512Mi | N/A |
| Mosquitto | 50m | 64Mi | 1Gi |

### Latency (Typical)

- Wake word detection: 200-500ms
- STT transcription (3s audio): 500-1000ms
- MQTT publish: 10-50ms
- n8n processing: 100-200ms
- HA API call: 100-300ms
- **Total**: 1-2 seconds from wake word to action

## Roadmap

- [ ] Add voice feedback (TTS responses)
- [ ] Support multiple microphones/rooms
- [ ] Intent classification with LLM (Ollama)
- [ ] Conversation context (multi-turn dialogs)
- [ ] Custom wake word training
- [ ] Integration with Grafana for command analytics
- [ ] Mobile app for remote voice commands

## References

- [Vosk Documentation](https://alphacephei.com/vosk/)
- [Mosquitto MQTT Broker](https://mosquitto.org/)
- [n8n Automation](https://n8n.io/)
- [Home Assistant API](https://developers.home-assistant.io/docs/api/rest/)

## Support

For issues or questions:
1. Check logs: `kubectl logs -n voice-assistant deployment/voice-agent`
2. Verify setup: Follow troubleshooting section above
3. GitHub Issues: https://github.com/Anh-Duy-Tran/home-server-gitops/issues
