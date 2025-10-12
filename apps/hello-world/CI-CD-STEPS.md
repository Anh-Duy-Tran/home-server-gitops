# GitOps CI/CD Pipeline Steps

## Overview
This document outlines the steps needed for a complete GitOps workflow with GitHub Actions, Docker Hub, and ArgoCD.

## Prerequisites
- Docker Hub account with credentials stored in GitHub Secrets
- Kubernetes cluster with ArgoCD installed
- ArgoCD application configured to watch this repository

## Pipeline Steps

### 1. Trigger Conditions
- Push to main branch
- Pull request to main branch
- Manual trigger (workflow_dispatch)

### 2. Build Steps

#### Step 2.1: Checkout Code
```bash
git checkout main
```

#### Step 2.2: Setup Build Environment
```bash
# Set up Node.js (for testing)
node --version
npm --version

# Set up Docker Buildx
docker buildx create --use
docker buildx version
```

#### Step 2.3: Generate Version Tags
```bash
# Generate semantic version based on:
# - Git tag (if exists)
# - Git commit SHA (short)
# - Timestamp

VERSION_TAG="v$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
LATEST_TAG="latest"
```

### 3. Test Steps (Optional but Recommended)

#### Step 3.1: Run Unit Tests
```bash
cd apps/hello-world
npm install
npm test  # If tests exist
```

#### Step 3.2: Run Linting
```bash
npm run lint  # If configured
```

### 4. Docker Build & Push

#### Step 4.1: Login to Docker Hub
```bash
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
```

#### Step 4.2: Build Docker Image
```bash
docker build \
  -t $DOCKER_USERNAME/hello-world:$VERSION_TAG \
  -t $DOCKER_USERNAME/hello-world:latest \
  ./apps/hello-world
```

#### Step 4.3: Push to Registry
```bash
docker push $DOCKER_USERNAME/hello-world:$VERSION_TAG
docker push $DOCKER_USERNAME/hello-world:latest
```

### 5. Update Kubernetes Manifests

#### Step 5.1: Update Deployment Manifest
```bash
# Update the image tag in deployment.yaml
sed -i "s|image: .*/hello-world:.*|image: $DOCKER_USERNAME/hello-world:$VERSION_TAG|g" \
  apps/hello-world/k8s/deployment.yaml
```

#### Step 5.2: Commit Manifest Changes
```bash
git config user.name "GitHub Actions"
git config user.email "actions@github.com"
git add apps/hello-world/k8s/deployment.yaml
git commit -m "ci: update image to $VERSION_TAG"
git push origin main
```

### 6. ArgoCD Sync (Automatic)

Since ArgoCD is configured with:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

ArgoCD will automatically:
1. Detect changes in the Git repository (within 3 minutes by default)
2. Pull the new manifests
3. Apply them to the cluster
4. Roll out the new deployment

### 7. Verification Steps

#### Step 7.1: Wait for ArgoCD Sync
```bash
# Using ArgoCD CLI (if available in CI environment)
argocd app wait hello-world --timeout 300

# OR using kubectl
kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/hello-world -n default
```

#### Step 7.2: Health Check
```bash
# Check if new version is deployed
APP_URL="http://your-app-url"
curl -f $APP_URL/health || exit 1

# Verify version
RESPONSE=$(curl -s $APP_URL)
echo $RESPONSE | grep "$VERSION_TAG"
```

## GitHub Actions Workflow Example

```yaml
name: GitOps CI/CD

on:
  push:
    branches: [ main ]
    paths:
      - 'apps/hello-world/**'
  workflow_dispatch:

env:
  DOCKER_USERNAME: ${{ secrets.DOCKER_USERNAME }}
  DOCKER_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3
      with:
        token: ${{ secrets.GITHUB_TOKEN }}

    - name: Generate version
      id: version
      run: |
        VERSION="v$(date +%Y%m%d)-$(git rev-parse --short HEAD)"
        echo "version=$VERSION" >> $GITHUB_OUTPUT

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2

    - name: Login to Docker Hub
      uses: docker/login-action@v2
      with:
        username: ${{ env.DOCKER_USERNAME }}
        password: ${{ env.DOCKER_PASSWORD }}

    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: ./apps/hello-world
        push: true
        tags: |
          ${{ env.DOCKER_USERNAME }}/hello-world:${{ steps.version.outputs.version }}
          ${{ env.DOCKER_USERNAME }}/hello-world:latest

    - name: Update Kubernetes manifests
      run: |
        sed -i "s|image: .*/hello-world:.*|image: ${{ env.DOCKER_USERNAME }}/hello-world:${{ steps.version.outputs.version }}|g" \
          apps/hello-world/k8s/deployment.yaml

    - name: Commit and push manifest updates
      run: |
        git config user.name "GitHub Actions"
        git config user.email "actions@github.com"
        git add apps/hello-world/k8s/deployment.yaml
        git commit -m "ci: update image to ${{ steps.version.outputs.version }}" || echo "No changes to commit"
        git push origin main
```

## Required GitHub Secrets

1. `DOCKER_USERNAME`: Your Docker Hub username
2. `DOCKER_PASSWORD`: Your Docker Hub password or access token
3. `GITHUB_TOKEN`: Automatically provided by GitHub Actions

## Manual GitOps Demo Steps (Without CI)

1. **Modify application code**
   ```bash
   # Edit app.js to change message/version
   ```

2. **Build new Docker image**
   ```bash
   docker build -t duytran410/hello-world:v2.0.0 ./apps/hello-world
   ```

3. **Push to Docker Hub**
   ```bash
   docker push duytran410/hello-world:v2.0.0
   ```

4. **Update deployment manifest**
   ```bash
   # Edit deployment.yaml
   # Change: image: duytran410/hello-world:latest
   # To:     image: duytran410/hello-world:v2.0.0
   ```

5. **Commit and push to GitHub**
   ```bash
   git add -A
   git commit -m "feat: update app to v2.0.0"
   git push origin main
   ```

6. **Watch ArgoCD auto-sync**
   ```bash
   # ArgoCD will detect changes within 3 minutes
   kubectl get application -n argocd hello-world --watch
   ```

7. **Verify deployment**
   ```bash
   curl -H "Host: hello.local" http://192.168.50.240:31954/
   # Should show the new message/version
   ```

## Notes

- ArgoCD polling interval is 3 minutes by default
- To trigger immediate sync: `argocd app sync hello-world`
- For production, use semantic versioning (1.0.0, 1.0.1, etc.)
- Consider using image digest instead of tags for immutability