# MiroTalk P2P - Video Conferencing

Simple P2P video conferencing solution.

## Features

- **P2P Video/Audio**: Direct peer-to-peer connections
- **Screen Sharing**: Share your screen with participants
- **Chat**: Text messaging during calls
- **No Account Required**: Just share a room link
- **Simpler than Jitsi**: No complex infrastructure, single Node.js app

## Deployment

### Deploy via ArgoCD

```bash
# Commit and push the manifests first
git add apps/mirotalk/
git commit -m "Add MiroTalk P2P video conferencing app"
git push

# Then deploy via ArgoCD
kubectl apply -f apps/mirotalk/app.yaml

# Check status
kubectl get application mirotalk -n argocd
kubectl get pods -n mirotalk
```

### Access

**URL**: `https://mirotalk.duytran.app`

No authentication needed - just:
1. Open the URL
2. Enter a room name
3. Share the link with others

## Configuration

### Change Domain

Edit `apps/mirotalk/manifests/deployment.yaml`:
```yaml
env:
- name: SERVER_URL
  value: "https://your-domain.com"
```

And `apps/mirotalk/manifests/ingress.yaml`:
```yaml
spec:
  rules:
  - host: your-domain.com
```

### Resource Scaling

For more users, increase resources in `deployment.yaml`:
```yaml
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

## Comparison with Jitsi

| Feature | MiroTalk P2P | Jitsi |
|---------|--------------|-------|
| Architecture | Single Node.js app | Multi-component (JVB, Jicofo, Prosody, Web) |
| Connection | P2P (browser-to-browser) | Uses video bridge (server-relayed) |
| Resource Usage | Low (~500MB RAM) | Higher (~4GB RAM total) |
| Scalability | Limited (2-4 users work best) | High (100+ users) |
| Setup | Simple | Complex |
| Firewall | No special ports | Needs UDP 10000 |

**Use MiroTalk when**:
- Small meetings (2-4 people)
- Simple setup required
- Lower resource usage preferred

**Use Jitsi when**:
- Larger meetings (5+ people)
- Better reliability needed
- Enterprise features required

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n mirotalk
kubectl logs -n mirotalk deployment/mirotalk
```

### Test locally
```bash
kubectl port-forward -n mirotalk svc/mirotalk 3000:80
# Open http://localhost:3000
```

### Common Issues

1. **P2P connection fails**: This is normal for P2P - if users are behind strict NAT/firewalls, connections may fail. Jitsi is more reliable in these cases.

2. **Room not found**: Room names are case-sensitive

## API Access

REST API available at `/api/v1/` with header:
```bash
authorization: mirotalkp2p_default_secret
```

Example:
```bash
curl -X POST https://mirotalk.duytran.app/api/v1/meeting \
  -H "authorization: mirotalkp2p_default_secret" \
  -H "Content-Type: application/json"
```

## Resources

- **GitHub**: https://github.com/miroslavpejic85/mirotalk
- **Docker Hub**: https://hub.docker.com/r/mirotalk/p2p
- **License**: AGPLv3 (open source)
