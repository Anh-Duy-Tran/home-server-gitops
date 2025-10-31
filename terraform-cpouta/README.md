# OpenTofu/Terraform cPouta k0s Infrastructure

Provisions a complete k0s cluster on CSC's cPouta (OpenStack) with:

- 1 controller node
- 4 worker nodes (configurable)
- 100GB block storage volumes automatically mounted at `/var/lib/k0s` on each worker
- Security groups for k0s cluster communication
- Floating IPs for external access

This configuration replicates the DigitalOcean setup but uses OpenStack resources.

---

## Prerequisites

### 1. CSC Account and cPouta Project

- CSC account with cPouta access
- Active cPouta project with sufficient quota:
  - 5 instances (1 controller + 4 workers)
  - 5 floating IPs
  - 400 GB volume storage (4 × 100GB)
  - ~50 GB ephemeral storage for instances

### 2. OpenRC File

Download your OpenRC file from cPouta dashboard:

1. Go to https://pouta.csc.fi
2. Navigate to **API Access** page
3. Click **Download OpenStack RC File**
4. Save as `project_XXXXXX-openrc.sh`

### 3. OpenStack CLI (Optional but Recommended)

Install OpenStack CLI to discover available resources:

```bash
# macOS
brew install openstackclient

# Linux
pip install python-openstackclient

# Verify installation
openstack --version
```

### 4. OpenTofu or Terraform

```bash
# OpenTofu (recommended - fully open source)
brew install opentofu

# Or Terraform
brew install terraform
```

### 5. SSH Key Pair

```bash
# Generate if you don't have one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

---

## Setup and Discovery

### 1. Source Your OpenRC File

**IMPORTANT:** You must source the OpenRC file before running any OpenStack or Terraform commands:

```bash
source project_XXXXXX-openrc.sh
```

You'll be prompted for your CSC password. This sets environment variables used for authentication:

- `OS_AUTH_URL`
- `OS_PROJECT_ID`
- `OS_PROJECT_NAME`
- `OS_USERNAME`
- `OS_PASSWORD`
- `OS_REGION_NAME`
- etc.

### 2. Discover Available Resources

#### List Available Images

```bash
openstack image list

# Common images:
# - Ubuntu-24.04
# - Ubuntu-22.04
# - Ubuntu-20.04
# - CentOS-7
# - RockyLinux-8
```

#### List Available Flavors

```bash
openstack flavor list

# Common cPouta flavors:
# NAME                vCPUs  RAM    Disk
# standard.tiny       1      1GB    80GB
# standard.small      1      2GB    80GB
# standard.medium     2      8GB    80GB
# standard.large      4      15GB   80GB
# standard.xlarge     6      30GB   80GB
# standard.xxlarge    8      60GB   80GB
# standard.3xlarge    8      120GB  80GB
```

#### List Your Networks

```bash
openstack network list

# You should see your project network: project_XXXXXXX
```

#### Check Your Keypairs

```bash
openstack keypair list

# The Terraform will create a new keypair named 'k0s-cluster-key'
```

### 3. Create Configuration File

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
image_name = "Ubuntu-24.04"
network_name = "project_2011111"  # Use your actual project network
controller_flavor = "standard.medium"
worker_flavor = "standard.medium"
worker_count = 4
ssh_public_key_path = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
ssh_user = "ubuntu"
```

---

## Deployment

### 1. Source OpenRC (Required Before Every Session)

```bash
source project_XXXXXX-openrc.sh
# Enter your CSC password when prompted
```

### 2. Initialize OpenTofu/Terraform

```bash
# If using OpenTofu
tofu init

# If using Terraform
terraform init
```

### 3. Plan

```bash
# OpenTofu
tofu plan

# Terraform
terraform plan
```

Review the plan to ensure it will create:

- 5 compute instances (1 controller + 4 workers)
- 5 floating IPs
- 4 volumes (100GB each)
- 6 security groups

### 4. Apply

```bash
# OpenTofu
tofu apply

# Terraform
terraform apply
```

Type `yes` when prompted.

**This will:**

1. Create security groups for cluster communication
2. Create 5 compute instances
3. Allocate and attach floating IPs
4. Create and attach 100GB volumes to workers
5. SSH into workers and mount volumes at `/var/lib/k0s`
6. Generate a `hosts.txt` file with IP mappings

**Deployment time:** ~5-10 minutes

### 5. Add DNS Entries to /etc/hosts

After successful deployment:

```bash
cat hosts.txt
# Copy the output and add to /etc/hosts:
sudo nano /etc/hosts
# Or append directly:
sudo sh -c 'cat hosts.txt >> /etc/hosts'
```

This allows you to SSH using hostnames:

```bash
ssh ubuntu@k0s-controller
ssh ubuntu@k0s-worker-1
```

**Note:** When you destroy the cluster, manually remove these entries from `/etc/hosts`.

### 6. Get Outputs

```bash
# OpenTofu
tofu output controller_public_ip
tofu output worker_public_ips
tofu output ssh_controller
tofu output -json k0sctl_hosts

# Terraform
terraform output controller_public_ip
terraform output worker_public_ips
terraform output ssh_controller
terraform output -json k0sctl_hosts
```

---

## Volume Configuration

The 100GB volumes are **automatically**:

- Created as OpenStack Cinder volumes
- Attached to worker nodes
- Formatted with ext4 filesystem
- Mounted at `/var/lib/k0s` (where k0s stores all data)
- Added to `/etc/fstab` for persistence across reboots

This ensures kubelet and containerd use the 100GB volume instead of the small root disk, **preventing DiskPressure issues**.

Verify volume mounting:

```bash
ssh ubuntu@k0s-worker-1 "df -h /var/lib/k0s"
```

---

## Key Differences from DigitalOcean

| Aspect             | DigitalOcean                        | cPouta (OpenStack)                 |
| ------------------ | ----------------------------------- | ---------------------------------- |
| **Authentication** | API token                           | OpenRC file (env vars)             |
| **Provider**       | `digitalocean`                      | `openstack`                        |
| **Compute**        | `digitalocean_droplet`              | `openstack_compute_instance_v2`    |
| **Volumes**        | `digitalocean_volume`               | `openstack_blockstorage_volume_v3` |
| **Firewall**       | `digitalocean_firewall`             | `openstack_networking_secgroup_v2` |
| **Public IPs**     | Automatic                           | Manual floating IP allocation      |
| **Networking**     | Automatic private network           | Must specify project network       |
| **SSH User**       | `root`                              | `ubuntu` (image-dependent)         |
| **Volume Device**  | `/dev/disk/by-id/scsi-0DO_Volume_*` | `/dev/vdb` (or next available)     |

---

## Cost Estimate (cPouta)

cPouta uses Billing Units (BUs). Approximate costs:

### Compute (per hour)

- **standard.medium** (2 vCPU, 8GB): ~1.6 BU/hour
  - Controller: 1 × 1.6 BU/hour
  - Workers: 4 × 1.6 BU/hour = 6.4 BU/hour
  - **Total compute**: ~8 BU/hour = ~5,760 BU/month

### Storage

- **Volume storage**: 400 GB × ~0.1 BU/GB/month = ~40 BU/month
- **Floating IPs**: 5 × minimal cost

### Total Estimate

~5,800 BU/month

**Note:** Actual costs depend on your CSC project allocation and billing rates. Check current rates at https://research.csc.fi/billing-and-monitoring

---

## Networking Architecture

### Security Groups Created

1. **k0s-cluster-ssh** - SSH access (port 22)
2. **k0s-cluster-api** - Kubernetes API (port 6443)
3. **k0s-cluster-web** - HTTP/HTTPS (ports 80, 443)
4. **k0s-cluster-konnectivity** - Konnectivity (ports 8132-8133)
5. **k0s-cluster-internal** - All inter-cluster communication (TCP, UDP, ICMP)

### IP Addressing

- **Public IPs**: Floating IPs from public pool (internet-accessible)
- **Private IPs**: From your project network (internal communication)
- **Calico VXLAN**: Recommended for pod networking (see CLAUDE.md)

**Important:** Unlike DigitalOcean, cPouta VPC doesn't block IPIP protocol, but VXLAN is still recommended for better compatibility.

---

## Usage with k0sctl

After deployment, generate k0sctl configuration:

```bash
# OpenTofu
tofu output -json k0sctl_hosts > k0sctl-hosts.json

# Terraform
terraform output -json k0sctl_hosts > k0sctl-hosts.json
```

Use this output to update your `k0sctl.yaml` configuration.

---

## SSH Access

### Using Floating IPs

```bash
# Controller
ssh ubuntu@$(tofu output -raw controller_public_ip)

# Workers (loop through all)
tofu output -json worker_public_ips | jq -r '.[]' | xargs -I {} ssh ubuntu@{}
```

### Using Hostnames (after adding to /etc/hosts)

```bash
ssh ubuntu@k0s-controller
ssh ubuntu@k0s-worker-1
ssh ubuntu@k0s-worker-2
ssh ubuntu@k0s-worker-3
ssh ubuntu@k0s-worker-4
```

---

## Troubleshooting

### OpenRC File Issues

**Problem:** Authentication errors

**Solution:**

```bash
# Verify environment variables are set
env | grep OS_

# Re-source the OpenRC file
source project_XXXXXX-openrc.sh

# Test authentication
openstack server list
```

### Volume Not Mounted

**Problem:** Volume not appearing in `/var/lib/k0s`

**Solution:**

```bash
# SSH into worker
ssh ubuntu@k0s-worker-1

# Check if volume is attached
lsblk

# Check if mounted
df -h /var/lib/k0s

# Manually mount if needed
sudo mount -a

# Check fstab entry
cat /etc/fstab | grep k0s
```

### Re-run Volume Provisioning

```bash
# OpenTofu
tofu taint 'null_resource.configure_volumes[0]'
tofu apply

# Terraform
terraform taint 'null_resource.configure_volumes[0]'
terraform apply
```

### SSH Connection Timeout

**Problem:** Cannot SSH to instances

**Checklist:**

1. Verify floating IPs are attached: `openstack server list`
2. Check security group rules: `openstack security group rule list k0s-cluster-ssh`
3. Verify SSH key: `ssh-add -L`
4. Check instance status: `openstack server show k0s-controller`

### Image Not Found

**Problem:** "Image Ubuntu-24.04 not found"

**Solution:**

```bash
# List available images
openstack image list

# Use the exact name from the list
# Update terraform.tfvars with correct image name
```

### Network Not Found

**Problem:** "Network project_XXXXXXX not found"

**Solution:**

```bash
# List your networks
openstack network list

# Copy the exact name of your project network
# Update terraform.tfvars
```

---

## Destroy Infrastructure

**Warning:** This will delete all resources and cannot be undone!

```bash
# OpenTofu
tofu destroy

# Terraform
terraform destroy
```

Type `yes` when prompted.

**Don't forget to:**

1. Remove entries from `/etc/hosts`
2. Clear any local state files if needed

---

## Security Considerations

### Current Configuration

- SSH, Kubernetes API, and web ports are open to `0.0.0.0/0` (internet)
- Inter-cluster communication restricted to cluster members only

### Production Recommendations

1. **Restrict SSH access** to your IP:

   ```hcl
   # In main.tf, modify ssh security group rule:
   remote_ip_prefix = "YOUR_IP/32"
   ```

2. **Use bastion host** for SSH access instead of direct floating IPs

3. **Restrict Kubernetes API** to authorized IPs:

   ```hcl
   remote_ip_prefix = "YOUR_IP/32"
   ```

4. **Use private network** for k0s cluster communication (already configured)

5. **Enable instance firewalls** (iptables/firewalld) as additional layer

---

## Integration with Existing Setup

### Using with k0sctl

Your existing `k8s/k0sctl.yaml` should work with minor modifications:

1. Update host addresses to use floating IPs
2. Change SSH user from `root` to `ubuntu`
3. Ensure Calico VXLAN mode is configured (already set in your config)

### ArgoCD and Applications

Once k0s is deployed, all your existing applications (`apps/*/`) will work without changes.

---

## Helpful Commands

### OpenStack CLI Cheat Sheet

```bash
# List all resources
openstack server list
openstack volume list
openstack floating ip list
openstack security group list
openstack network list

# Get details
openstack server show k0s-controller
openstack volume show k0s-worker-1-storage

# Console access (if SSH fails)
openstack console url show k0s-controller

# Reboot instance
openstack server reboot k0s-controller

# Delete stuck resources
openstack server delete <server-id>
openstack volume delete <volume-id>
```

### OpenTofu/Terraform State

```bash
# Show state
tofu state list
tofu state show openstack_compute_instance_v2.controller

# Import existing resource
tofu import openstack_compute_instance_v2.controller <instance-id>

# Remove resource from state (doesn't delete)
tofu state rm openstack_compute_instance_v2.controller
```

---

## Resources

### cPouta Documentation

- [cPouta User Guide](https://docs.csc.fi/cloud/pouta/)
- [cPouta VM Flavors](https://docs.csc.fi/cloud/pouta/vm-flavors-and-billing/)
- [cPouta Images](https://docs.csc.fi/cloud/pouta/images/)
- [cPouta Networking](https://docs.csc.fi/cloud/pouta/networking/)

### OpenStack Provider

- [Provider Documentation](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [CSC Terraform Example](https://github.com/CSCfi/terraform-openstack-example)

### OpenTofu

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Migration from Terraform](https://opentofu.org/docs/intro/migration/)

---

## TODO / Future Improvements

- [ ] Add support for GPU flavors (io.XXX series)
- [ ] Implement backup strategy for volumes
- [ ] Add monitoring with cPouta's built-in metrics
- [ ] Create separate security groups for production/staging
- [ ] Add support for multiple availability zones
- [ ] Integrate with CSC's identity federation
- [ ] Add automated testing with kitchen-terraform

---

## Support

For issues:

1. **cPouta/CSC**: servicedesk@csc.fi
2. **This repo**: [GitHub Issues](https://github.com/Anh-Duy-Tran/home-server-gitops/issues)
3. **OpenStack Provider**: [GitHub Issues](https://github.com/terraform-provider-openstack/terraform-provider-openstack/issues)

---

## License

Same as parent repository.
