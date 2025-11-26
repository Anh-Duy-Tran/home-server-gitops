# Voice Assistant Quick Start

Get your voice-controlled home automation running in 15 minutes.

## Prerequisites Checklist

- [ ] Kubernetes cluster running (k0s)
- [ ] USB microphone plugged into a worker node (Raspberry Pi)
- [ ] Docker installed locally
- [ ] Home Assistant running with API enabled
- [ ] n8n running in the cluster

## 5-Step Setup

### 1. Label Your Microphone Node (2 min)

```bash
# Find your nodes
kubectl get nodes

# Label the node with the microphone (your Home Assistant Pi)
kubectl label node <your-pi-node-name> voice-capable=true
```

### 2. Build and Push Voice Agent Image (5 min)

```bash
cd apps/voice-assistant

# Build (includes downloading Vosk model - ~40MB)
docker build -t <your-registry>/voice-agent:latest .

# Push to your registry
docker push <your-registry>/voice-agent:latest

# Update the image path in manifests/voice-agent.yaml manually
# Change: image: your-registry/voice-agent:latest
# To:     image: <your-registry>/voice-agent:latest
```

### 3. Deploy to Kubernetes (2 min)

```bash
# Deploy via ArgoCD
kubectl apply -f app.yaml

# Wait for sync
kubectl wait --for=condition=Synced application/voice-assistant -n argocd --timeout=300s

# Check pods
kubectl get pods -n voice-assistant
```

Expected output:
```
NAME                           READY   STATUS    RESTARTS   AGE
mosquitto-xxxxxxxxxx-xxxxx     1/1     Running   0          1m
voice-agent-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

### 4. Configure n8n (5 min)

#### 4.1 Get Home Assistant Token

1. Go to Home Assistant → Profile → Long-Lived Access Tokens
2. Create token named "n8n voice control"
3. Copy the token

#### 4.2 Set up n8n

```bash
# Port-forward n8n (if not already exposed)
kubectl port-forward -n n8n svc/n8n 5678:5678
```

Open http://localhost:5678

**Add MQTT Credential:**
1. Settings → Credentials → New Credential
2. Select "MQTT"
3. Configure:
   - Name: Voice Assistant MQTT
   - Protocol: mqtt
   - Host: `mosquitto.voice-assistant.svc.cluster.local`
   - Port: 1883
   - Leave username/password empty
4. Save

**Add Home Assistant Credential:**
1. Settings → Credentials → New Credential
2. Select "HTTP Header Auth"
3. Configure:
   - Name: Home Assistant Bearer Token
   - Header Name: Authorization
   - Value: `Bearer YOUR_TOKEN_HERE` (paste your HA token)
4. Save

**Import Workflow:**
1. Workflows → Import from File
2. Upload `n8n-integration.json`
3. Update nodes:
   - MQTT Trigger: Select "Voice Assistant MQTT"
   - Call Home Assistant: Select "Home Assistant Bearer Token"
   - Call Home Assistant URL: Update to your HA (e.g., `http://homeassistant.default.svc.cluster.local:8123`)
4. Click "Activate" (toggle in top right)

### 5. Test It! (1 min)

```bash
# Watch logs
kubectl logs -n voice-assistant deployment/voice-agent -f
```

**Speak into your microphone:**

```
"Hey assistant, turn on the kitchen light"
```

You should see:
```
2025-11-26 10:30:15 - Wake phrase detected: 'hey assistant'
2025-11-26 10:30:18 - Command transcribed: 'turn on the kitchen light'
2025-11-26 10:30:18 - Published command: turn on the kitchen light
```

And your kitchen light should turn on! 🎉

## Supported Commands (Default)

Update these in the n8n workflow to match your Home Assistant entities:

- **"turn on the kitchen light"** → `light.kitchen_light`
- **"turn off the kitchen light"** → `light.kitchen_light`
- **"turn on the living room light"** → `light.living_room_light`
- **"lock the door"** → `lock.front_door`
- **"unlock the door"** → `lock.front_door`
- **"movie time"** → `scene.movie_time`
- **"what's the temperature"** → `sensor.living_room_temperature`

## Customizing Wake Phrases

Edit `manifests/voice-agent.yaml`:

```yaml
data:
  WAKE_PHRASES: "hey jarvis,computer,ok google"
```

Then restart:
```bash
kubectl rollout restart deployment/voice-agent -n voice-assistant
```

## Troubleshooting

### Voice agent not starting
```bash
# Check logs
kubectl logs -n voice-assistant deployment/voice-agent

# Common issue: not running on microphone node
kubectl describe pod -n voice-assistant -l app=voice-agent
# Look for: "0/X nodes are available: X node(s) didn't match Pod's node affinity"
# Solution: Verify node label and nodeSelector
```

### Wake word not detected
```bash
# Check audio devices
kubectl exec -it -n voice-assistant deployment/voice-agent -- \
  python3 -c "import sounddevice as sd; print(sd.query_devices())"

# Should show your USB microphone
```

### Commands not reaching Home Assistant
```bash
# Test MQTT
kubectl port-forward -n voice-assistant svc/mosquitto 1883:1883

# In another terminal
mosquitto_sub -h localhost -t "home/voice/commands" -v

# Speak a command and verify JSON appears
```

## Next Steps

1. **Add more commands**: Edit n8n workflow's "Parse Voice Command" node
2. **Secure MQTT**: Enable authentication (see README.md)
3. **Add more entities**: Update n8n to control your specific devices
4. **Monitor usage**: Check n8n execution history for command analytics

## Reference

- Full documentation: [README.md](README.md)
- n8n workflow details: [n8n-integration.json](n8n-integration.json)
- Architecture diagram: See README.md

---

**Questions?** Check the troubleshooting section in [README.md](README.md)
