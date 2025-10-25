# Terraform DigitalOcean k0s Infrastructure

Provisions a complete k0s cluster on DigitalOcean with:

- 1 controller node
- 4 worker nodes (configurable)
- 100GB block storage volumes automatically mounted at `/var/lib/k0s` on each worker
- Firewall rules for k0s cluster communication

## Prerequisites

1. **DigitalOcean API Token:**

   ```bash
   # Get your token from: https://cloud.digitalocean.com/account/api/tokens
   export DO_TOKEN="your_digitalocean_token"
   ```

2. **SSH key pair:**

   ```bash
   # Generate if you don't have one
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   ```

3. **Terraform installed:**
   ```bash
   brew install terraform
   ```

## Usage

1. **Create terraform.tfvars:**

   ```bash
   cat > terraform.tfvars << EOF
   do_token              = "your_digitalocean_api_token"
   region                = "fra1"
   controller_size       = "g-2vcpu-8gb"
   worker_size           = "g-2vcpu-8gb"
   worker_count          = 4
   ssh_public_key_path   = "~/.ssh/id_rsa.pub"
   ssh_private_key_path  = "~/.ssh/id_rsa"
   EOF
   ```

2. **Initialize Terraform:**

   ```bash
   terraform init
   ```

3. **Plan:**

   ```bash
   terraform plan
   ```

4. **Apply:**

   ```bash
   terraform apply
   ```

   This will:

   - Create 5 droplets (1 controller + 4 workers)
   - Create 4 x 100GB volumes
   - Attach volumes to workers
   - Mount volumes at `/var/lib/k0s` automatically
   - Configure firewall rules

5. **Get outputs:**

   ```bash
   terraform output controller_ip
   terraform output worker_ips
   terraform output ssh_controller
   terraform output ssh_workers
   ```

6. **Use with k0sctl:**
   ```bash
   terraform output -json k0sctl_hosts
   ```

## Volume Configuration

The 100GB volumes are **automatically**:

- Attached to worker nodes
- Mounted at `/var/lib/k0s` (where k0s stores all data)
- Added to `/etc/fstab` for persistence across reboots

This ensures kubelet and containerd use the 100GB volume instead of the small root disk, **preventing DiskPressure issues**.

## Cost Estimate (using General Purpose droplets)

- Controller: g-2vcpu-8gb
- Workers: 4 × g-2vcpu-8gb
- Volumes: 4 × 100GB = $40/mo
- **Total: Check current DO pricing**

## Regions

Common regions:

- `fra1` - Frankfurt, Germany
- `nyc1`, `nyc3` - New York, USA
- `sfo3` - San Francisco, USA
- `sgp1` - Singapore
- `lon1` - London, UK

## Droplet Sizes

### General Purpose (g- prefix, recommended)

| Size         | vCPU | RAM  |
| ------------ | ---- | ---- |
| g-2vcpu-8gb  | 2    | 8GB  |
| g-4vcpu-16gb | 4    | 16GB |
| g-8vcpu-32gb | 8    | 32GB |

### Basic (s- prefix, older)

| Size        | vCPU | RAM |
| ----------- | ---- | --- |
| s-2vcpu-2gb | 2    | 2GB |
| s-2vcpu-4gb | 2    | 4GB |
| s-4vcpu-8gb | 4    | 8GB |

## Destroy

```bash
terraform destroy
```

## SSH Access

After apply:

```bash
# Controller
ssh root@$(terraform output -raw controller_ip)

# Workers
terraform output -json worker_ips | jq -r '.[]' | xargs -I {} ssh root@{}
```

## Troubleshooting

### Volume not mounted

Check volume attachment:

```bash
ssh root@<worker-ip> "lsblk"
ssh root@<worker-ip> "df -h /var/lib/k0s"
```

### Re-run volume provisioning

```bash
terraform taint 'null_resource.configure_volumes[0]'
terraform apply
```
