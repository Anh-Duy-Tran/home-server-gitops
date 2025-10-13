# Hello World GitOps Application

This is a demo Node.js application deployed using GitOps principles with ArgoCD.

## Architecture

```
GitHub Repo → GitHub Actions → Docker Hub → ArgoCD → Kubernetes
```

## Components

- **Application**: Simple Express.js server
- **Container Registry**: Docker Hub
- **GitOps Tool**: ArgoCD
- **Ingress Controller**: Traefik
- **Target**: Kubernetes cluster

## Directory Structure

```
hello-world/
├── app.js                  # Main application
├── package.json            # Node dependencies
├── Dockerfile              # Container definition
├── argocd-app.yaml         # ArgoCD application config
├── CI-CD-STEPS.md          # Detailed CI/CD documentation
├── k8s/                    # Kubernetes manifests
│   ├── deployment.yaml     # App deployment
│   ├── service.yaml        # ClusterIP service
│   ├── ingress.yaml        # Traefik ingress
│   └── kustomization.yaml  # Kustomize config
└── README.md               # This file
```

## Quick Start

### Local Development

1. Install dependencies:

```bash
npm install
```

2. Run locally:

```bash
npm start
# Access at http://localhost:3000
```

### Manual Deployment

1. Build and push Docker image:

```bash
docker build -t yourusername/hello-world:v1.0.0 .
docker push yourusername/hello-world:v1.0.0
```

2. Update `k8s/deployment.yaml` with new image tag

3. Commit and push to GitHub:

```bash
git add -A
git commit -m "feat: update to v1.0.0"
git push origin main
```

4. ArgoCD will auto-sync within 3 minutes

### Access the Application

```bash
# Using Host header
curl -H "Host: hello.local" http://<node-ip>:<node-port>/

# Example with current setup
curl -H "Host: hello.local" http://192.168.50.240:31954/
```

## GitHub Actions Setup

### Required Secrets

Add these secrets to your GitHub repository:

1. `DOCKER_USERNAME` - Your Docker Hub username
2. `DOCKER_PASSWORD` - Docker Hub password or access token

### Workflow Triggers

The GitHub Action runs when:

- Code is pushed to `main` branch
- Changes are made in `apps/hello-world/` directory
- Manual trigger via GitHub UI

## ArgoCD Configuration

The application is configured with:

- **Auto-sync**: Enabled
- **Self-heal**: Enabled
- **Prune**: Enabled

This means ArgoCD will:

1. Automatically detect Git changes
2. Deploy new versions without manual intervention
3. Correct any drift from desired state
4. Remove resources not defined in Git

## Testing GitOps Flow

1. **Make a code change**:

```javascript
// app.js - Change the message
message: "New message here!";
```

2. **Commit and push**:

```bash
git add app.js
git commit -m "feat: update message"
git push origin main
```

3. **Watch the magic happen**:

- GitHub Actions builds new image
- Updates deployment.yaml with new tag
- ArgoCD detects change and deploys

4. **Verify deployment**:

```bash
curl -H "Host: hello.local" http://<node-ip>:<node-port>/
# Should show new message
```

## Monitoring

Check application status:

```bash
# ArgoCD application status
kubectl get application -n argocd hello-world

# Pod status
kubectl get pods -l app=hello-world

# Logs
kubectl logs -l app=hello-world
```

## Rollback

If needed, rollback via:

1. **Git revert** (recommended for GitOps):

```bash
git revert HEAD
git push origin main
```

2. **ArgoCD UI/CLI** (temporary):

```bash
argocd app rollback hello-world
```

## Troubleshooting

### Image Pull Errors

- Verify Docker Hub credentials
- Check image exists: `docker pull yourusername/hello-world:tag`

### ArgoCD Not Syncing

- Check application status: `kubectl describe application hello-world -n argocd`
- Verify Git repository is accessible
- Manual sync: `argocd app sync hello-world`

### Ingress Not Working

- Verify Traefik is running
- Check ingress: `kubectl get ingress hello-world`
- Test service directly: `kubectl port-forward svc/hello-world 8080:80`

## Next Steps

- [ ] Add health checks and readiness probes ✓
- [ ] Implement proper versioning strategy
- [ ] Add monitoring (Prometheus/Grafana)
- [ ] Set up staging environment
- [ ] Add security scanning in CI
- [ ] Implement blue-green deployments

