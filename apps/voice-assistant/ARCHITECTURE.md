# Voice Assistant Architecture

## Overview

Local, privacy-focused voice control system for Home Assistant running on Kubernetes with zero cloud dependencies.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User Interaction                           │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ "Hey assistant, turn on the light"
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Step 1: Audio Capture (Pi Node)                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ USB Microphone → sounddevice → 16kHz PCM audio stream       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Raw audio (bytes)
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Step 2: Wake Word Detection (voice-agent)              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Vosk Recognizer (partial results)                           │   │
│  │   - Continuous processing                                    │   │
│  │   - Matches: "hey assistant", "hey wolt", "ok assistant"     │   │
│  │   - Latency: ~200-500ms                                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                    Wake phrase detected! │
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│          Step 3: Command Recording (voice-agent)                    │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Collect next 3 seconds of audio                              │   │
│  │   - 16kHz × 3s = 48,000 samples                              │   │
│  │   - ~96KB raw data                                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Command audio
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│        Step 4: Speech-to-Text (voice-agent + Vosk)                  │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Vosk Model: vosk-model-small-en-us-0.15                     │   │
│  │   - Size: ~40MB                                              │   │
│  │   - Latency: 500-1000ms for 3s audio                         │   │
│  │   - Output: "turn on the light"                              │   │
│  │   - Confidence: 0.85-0.95                                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Transcribed text
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Step 5: MQTT Publish (voice-agent)                        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Topic: home/voice/commands                                   │   │
│  │ Payload:                                                     │   │
│  │ {                                                            │   │
│  │   "user": "duy",                                             │   │
│  │   "text": "turn on the light",                               │   │
│  │   "confidence": 0.9,                                         │   │
│  │   "source": "k8s-voice-assistant",                           │   │
│  │   "timestamp": "2025-11-26T10:30:18.123456"                  │   │
│  │ }                                                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ MQTT message (QoS 1)
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                Step 6: MQTT Broker (Mosquitto)                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Service: mosquitto.voice-assistant.svc.cluster.local:1883    │   │
│  │ - Persistent storage (1Gi PVC)                               │   │
│  │ - QoS 1 (at least once delivery)                             │   │
│  │ - Message logging enabled                                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Fanout to subscribers
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Step 7: n8n MQTT Trigger (n8n workflow)                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Subscribed to: home/voice/commands                           │   │
│  │ Receives JSON payload                                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ JSON payload
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│         Step 8: Command Parsing (n8n function node)                 │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Parse text: "turn on the light"                              │   │
│  │ Match patterns:                                              │   │
│  │   - "kitchen" + "light" + "on" → light.kitchen_light        │   │
│  │   - "door" + "lock" → lock.front_door                        │   │
│  │   - "movie time" → scene.movie_time                          │   │
│  │                                                              │   │
│  │ Output:                                                      │   │
│  │ {                                                            │   │
│  │   "service": "light/turn_on",                                │   │
│  │   "entity_id": "light.kitchen_light"                         │   │
│  │ }                                                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ HA service call params
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│        Step 9: Home Assistant API Call (n8n HTTP node)              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ POST http://homeassistant:8123/api/services/light/turn_on   │   │
│  │ Headers:                                                     │   │
│  │   Authorization: Bearer <long-lived-token>                   │   │
│  │ Body:                                                        │   │
│  │ {                                                            │   │
│  │   "entity_id": "light.kitchen_light"                         │   │
│  │ }                                                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ HTTP 200 OK
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Step 10: Action Execution                        │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Home Assistant executes:                                     │   │
│  │   - Sends command to smart light controller                  │   │
│  │   - Light turns on                                           │   │
│  │   - Updates entity state in HA database                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Physical state change
                                 ▼
                        💡 Light turns ON!
```

## Component Architecture

### 1. Voice Agent Pod

**Image**: Custom Python application
**Base**: python:3.11-slim
**Size**: ~500MB (includes Vosk model)

**Dependencies**:
- `vosk==0.3.45` - Speech recognition
- `sounddevice==0.4.6` - Audio capture
- `paho-mqtt==1.6.1` - MQTT client

**Capabilities**:
- Runs with `privileged: true` (audio device access)
- `hostNetwork: true` (direct device access)
- Mounts `/dev/snd` from host

**Node Requirements**:
- Must run on node with USB microphone
- Requires ALSA audio drivers
- Typical: Raspberry Pi with USB mic

**Resource Limits**:
```yaml
requests:
  cpu: 500m
  memory: 512Mi
limits:
  cpu: 1000m
  memory: 1Gi
```

**Health Check**: `pgrep voice_agent.py` every 30s

### 2. Mosquitto MQTT Broker

**Image**: eclipse-mosquitto:2.0.18
**Size**: ~10MB

**Configuration**:
- Port: 1883 (MQTT)
- Protocol: MQTT v3.1.1
- Authentication: Anonymous (optional auth later)
- Persistence: Enabled (1Gi PVC)

**Resource Limits**:
```yaml
requests:
  cpu: 100m
  memory: 128Mi
limits:
  cpu: 500m
  memory: 256Mi
```

**Topics**:
- `home/voice/commands` - Voice commands (published by voice-agent)
- `$SYS/#` - Broker statistics

**Storage**: 1Gi PVC (do-block-storage) for message persistence

### 3. n8n Workflow

**Trigger**: MQTT Trigger node
**Processing**: 3 nodes
1. Parse Voice Command (function)
2. Skip Unknown Commands (if)
3. Call Home Assistant (HTTP request)

**Credentials Required**:
- MQTT: mosquitto.voice-assistant.svc.cluster.local:1883
- Home Assistant: Bearer token with API access

**Workflow File**: `n8n-integration.json` (importable)

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Namespace: voice-assistant                           │   │
│  │                                                       │   │
│  │  ┌──────────────┐     ┌──────────────┐              │   │
│  │  │ voice-agent  │────>│  mosquitto   │              │   │
│  │  │              │     │  Service     │              │   │
│  │  │ hostNetwork  │     │ ClusterIP    │              │   │
│  │  │              │     │ :1883        │              │   │
│  │  └──────────────┘     └──────┬───────┘              │   │
│  │                              │                       │   │
│  └──────────────────────────────┼───────────────────────┘   │
│                                 │ MQTT                      │
│  ┌──────────────────────────────┼───────────────────────┐   │
│  │ Namespace: n8n               │                       │   │
│  │                              │                       │   │
│  │                        ┌─────▼───────┐              │   │
│  │                        │     n8n     │              │   │
│  │                        │  Workflow   │              │   │
│  │                        │             │              │   │
│  │                        └─────┬───────┘              │   │
│  └──────────────────────────────┼───────────────────────┘   │
│                                 │ HTTP                      │
│  ┌──────────────────────────────┼───────────────────────┐   │
│  │ Namespace: default           │                       │   │
│  │                              │                       │   │
│  │                        ┌─────▼─────────┐            │   │
│  │                        │ homeassistant │            │   │
│  │                        │ Service       │            │   │
│  │                        │ ClusterIP     │            │   │
│  │                        │ :8123         │            │   │
│  │                        └───────────────┘            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Security Model

### Audio Privacy
- ✅ **All audio processing is local** (no cloud APIs)
- ✅ **Audio never leaves the cluster**
- ✅ **No recording/storage** (streaming only)
- ✅ **No telemetry or analytics**

### Authentication
- **MQTT**: Currently anonymous (within cluster)
  - Future: Add username/password auth
  - Isolation: Network policies can restrict access
- **Home Assistant**: Bearer token authentication
  - Stored in n8n credentials (encrypted at rest)
  - Requires long-lived access token

### Privileged Access
- **Voice agent runs privileged** for audio device access
  - Risk: Container escape = node compromise
  - Mitigation: Dedicated Pi node, minimal attack surface
  - Alternative: Use host audio with socket binding (complex)

### Network Isolation
- **MQTT broker**: ClusterIP only (not exposed externally)
- **Voice agent**: hostNetwork (required for audio)
- **n8n/HA**: Internal cluster communication only

## Performance Characteristics

### Latency Breakdown
| Stage | Latency | Notes |
|-------|---------|-------|
| Wake word detection | 200-500ms | Partial results, continuous |
| Command recording | 3000ms | Configurable (POST_WAKE_RECORD_SECONDS) |
| STT transcription | 500-1000ms | Vosk small model, depends on CPU |
| MQTT publish | 10-50ms | Local network, QoS 1 |
| n8n processing | 100-200ms | Command parsing + routing |
| HA API call | 100-300ms | REST API roundtrip |
| HA execution | 200-1000ms | Device-dependent (Z-Wave, Zigbee, WiFi) |
| **Total (user perspective)** | **4-6 seconds** | From "Hey assistant" to light on |

### Optimization Opportunities
1. **Faster STT**: Use Vosk medium/large model (higher accuracy, +500ms)
2. **GPU acceleration**: Run on GPU node with CUDA (5-10x faster STT)
3. **Whisper model**: Better accuracy but slower (~2-3s for 3s audio)
4. **Reduce recording time**: 2s instead of 3s (saves 1s, may cut off commands)
5. **Wake word engine**: Use Porcupine/Precise (more accurate, lower latency)

### Resource Usage
| Component | CPU (idle) | CPU (active) | Memory | Storage |
|-----------|-----------|--------------|--------|---------|
| Voice agent | 50-100m | 500-800m | 512Mi | - |
| Mosquitto | 10m | 50m | 64Mi | 1Gi |
| n8n (workflow) | - | 50m | - | - |
| **Total** | ~100m | ~900m | 576Mi | 1Gi |

### Scalability
- **Current**: Single voice agent on one node
- **Multi-room**: Deploy multiple voice-agent pods on different nodes
  - Each pod on a node with a microphone
  - All publish to same MQTT topic
  - n8n workflow handles commands from all agents
  - Use `source` field in JSON to identify room

## Technology Choices

### Why Vosk over Whisper?
- ✅ Faster inference (500ms vs 2-3s)
- ✅ Lower memory (512Mi vs 2Gi+)
- ✅ No GPU required
- ✅ Runs on Raspberry Pi
- ❌ Lower accuracy (~85% vs 95%+)
- **Decision**: Speed > accuracy for home commands

### Why MQTT over gRPC/HTTP?
- ✅ Decoupled architecture (n8n can restart without affecting voice agent)
- ✅ Message persistence (QoS 1)
- ✅ Easy debugging (mosquitto_sub)
- ✅ Multi-subscriber support (future: multiple n8n workflows)
- ✅ Standard IoT protocol

### Why n8n over Direct HA API?
- ✅ Visual workflow editing (no code changes)
- ✅ Easy to add complex logic (conditions, loops)
- ✅ Multiple actions per command
- ✅ Integration with other services (Slack notifications, databases)
- ✅ Execution history and debugging
- ❌ Adds 100-200ms latency
- **Decision**: Flexibility > latency

### Why Not Cloud STT (Google, AWS, Azure)?
- ✅ Privacy (audio stays local)
- ✅ No internet required
- ✅ No API costs
- ✅ Lower latency (no cloud roundtrip)
- ❌ Lower accuracy
- ❌ Requires cluster resources
- **Decision**: Privacy > accuracy

## Failure Modes and Recovery

### Voice Agent Crashes
- **Detection**: Liveness probe fails (pgrep)
- **Recovery**: Kubernetes restarts pod (RestartPolicy: Always)
- **Downtime**: ~30s (probe failure + restart)
- **User Impact**: Commands ignored until restart

### MQTT Broker Down
- **Detection**: Voice agent logs connection errors
- **Recovery**: Automatic reconnect (paho-mqtt client)
- **Data Loss**: Messages during outage (not persisted)
- **User Impact**: Commands ignored, voice agent keeps running

### n8n Workflow Disabled
- **Detection**: No HA commands executed
- **Recovery**: Manual (activate workflow in n8n UI)
- **Data Loss**: Messages still in MQTT broker (can replay)
- **User Impact**: Commands transcribed but not executed

### Home Assistant Unreachable
- **Detection**: n8n HTTP node returns 500/503
- **Recovery**: Automatic retry (n8n retry policy)
- **User Impact**: Command delayed or failed

### Microphone Disconnected
- **Detection**: sounddevice raises exception
- **Recovery**: Voice agent crashes, restarts, retries
- **User Impact**: No wake word detection

## Future Enhancements

### Phase 1: Stability & Reliability
- [ ] Add Prometheus metrics to voice agent
- [ ] Grafana dashboard for command analytics
- [ ] Alerting on voice agent failures
- [ ] MQTT authentication and TLS
- [ ] Rate limiting (prevent command spam)

### Phase 2: Intelligence
- [ ] Intent classification with Ollama (local LLM)
- [ ] Multi-turn conversations (context tracking)
- [ ] Natural language understanding (parse complex commands)
- [ ] Confirmation requests for destructive actions (unlock door)

### Phase 3: Multi-Room
- [ ] Deploy voice agents on multiple nodes
- [ ] Room identification in MQTT payload
- [ ] Room-specific command routing (closest light, etc.)
- [ ] Audio feedback per room (TTS responses)

### Phase 4: Advanced Features
- [ ] Voice profiles (speaker identification)
- [ ] Custom wake word training
- [ ] Offline command queuing (if HA down)
- [ ] Mobile app for remote voice commands
- [ ] Integration with calendar/reminders

## Monitoring and Observability

### Logs
```bash
# Voice agent
kubectl logs -n voice-assistant deployment/voice-agent -f

# MQTT broker
kubectl logs -n voice-assistant deployment/mosquitto -f

# n8n executions (via UI)
kubectl port-forward -n n8n svc/n8n 5678:5678
# → http://localhost:5678 → Workflows → Executions
```

### Metrics (Prometheus)
**Potential metrics** (not yet implemented):
- `voice_commands_total` - Counter of commands processed
- `voice_wake_detections_total` - Counter of wake word triggers
- `voice_stt_duration_seconds` - Histogram of transcription latency
- `voice_mqtt_publish_errors_total` - Counter of MQTT failures
- `mosquitto_messages_received_total` - MQTT broker message count

### Debugging
```bash
# Test MQTT directly
kubectl port-forward -n voice-assistant svc/mosquitto 1883:1883
mosquitto_pub -h localhost -t "home/voice/commands" -m '{"user":"test","text":"turn on the light","confidence":1.0,"source":"manual","timestamp":"2025-11-26T10:00:00"}'

# Check n8n receives it (should trigger workflow)

# Test Home Assistant API directly
kubectl exec -n n8n deployment/n8n -- \
  curl -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "light.kitchen_light"}' \
  http://homeassistant.default.svc.cluster.local:8123/api/services/light/turn_on
```

## References

- [Vosk API Documentation](https://alphacephei.com/vosk/api)
- [Mosquitto Configuration](https://mosquitto.org/man/mosquitto-conf-5.html)
- [n8n MQTT Trigger](https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.mqtttrigger/)
- [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/)
- [Kubernetes Audio Devices](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#host-namespaces)
