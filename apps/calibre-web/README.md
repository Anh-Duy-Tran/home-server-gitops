# Calibre-Web

Web app for browsing, reading and downloading eBooks stored in a Calibre database.

## Features

- Browse, read, and download eBooks
- Web-based eBook reader
- Support for multiple formats (EPUB, MOBI, PDF, etc.)
- User management
- Send books to Kindle
- OPDS feed for eBook readers

## Deployment

### Deploy with ArgoCD

```bash
kubectl apply -f apps/calibre-web/app.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n calibre-web

# Check service
kubectl get svc -n calibre-web

# Check PVCs
kubectl get pvc -n calibre-web
```

## Access

### Local Port Forward

```bash
kubectl port-forward -n calibre-web svc/calibre-web 8083:8083
```

Then access at: http://localhost:8083

### Default Credentials

- Username: `admin`
- Password: `admin123`

**IMPORTANT**: Change the default password after first login!

## Configuration

### Storage

Two persistent volumes are created:
- `calibre-web-config`: 1Gi - Application configuration
- `calibre-web-books`: 50Gi - Calibre library and books

### Initial Setup

1. On first login, you'll need to specify the Calibre library location
2. Set the path to: `/books`
3. Upload your Calibre library to the `calibre-web-books` PVC

### Uploading Books

To upload your existing Calibre library:

```bash
# Get the pod name
POD_NAME=$(kubectl get pod -n calibre-web -l app=calibre-web -o jsonpath='{.items[0].metadata.name}')

# Copy your Calibre library
kubectl cp /path/to/your/calibre-library $POD_NAME:/books -n calibre-web
```

## Public Ingress (Optional)

To enable public access via Traefik:

1. Uncomment `ingress.yaml` in `manifests/kustomization.yaml`
2. Update the hostname in `manifests/ingress.yaml` if needed
3. Commit and push changes
4. ArgoCD will auto-sync the changes

## Resources

- **GitHub**: https://github.com/janeczku/calibre-web
- **Docker Image**: https://docs.linuxserver.io/images/docker-calibre-web
- **Calibre**: https://calibre-ebook.com/

## Troubleshooting

### Check Logs

```bash
kubectl logs -n calibre-web -l app=calibre-web --tail=50
```

### Check Events

```bash
kubectl get events -n calibre-web --sort-by='.lastTimestamp'
```

### Restart Deployment

```bash
kubectl rollout restart deployment/calibre-web -n calibre-web
```
