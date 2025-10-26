# Local Ray Development

Develop Ray applications locally and execute on your cloud cluster.

## Setup Options

### Option 1: VS Code + Jupyter (Recommended with uv)

```bash
# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment with uv
uv venv

# Install dependencies from pyproject.toml (much faster!)
uv pip install -e .

# Run Jupyter (no activation needed!)
uv run jupyter lab --notebook-dir=.
```

Then open `.ipynb` files in VS Code with Jupyter extension.

**Quick commands with uv:**
```bash
# Add a new package and update pyproject.toml
uv add <package>

# Run without activating venv
uv run jupyter lab

# Sync/reinstall all dependencies
uv sync
```

### Option 2: Docker Compose

```bash
# From apps/ray directory
docker-compose up

# Access Jupyter at http://localhost:8888
```

## Connect to Cloud Ray Cluster

**Terminal 1 - Port forward Ray:**
```bash
kubectl port-forward -n ray-system svc/raycluster-sample-head-svc 10001:10001 8265:8265
```

**Terminal 2 - Port forward MinIO (optional):**
```bash
kubectl port-forward -n minio svc/minio 9000:9000
```

**In notebook:**
```python
import ray
ray.init("ray://localhost:10001")
```

## Notebooks

- `01_ray_cluster_connection.ipynb` - Connection template
- Add your notebooks here...

## Tips

- Keep port forwards running while developing
- Ray Dashboard: http://localhost:8265
- All Ray tasks execute on your cloud cluster
- Results saved to MinIO (accessible from both local and cluster)
