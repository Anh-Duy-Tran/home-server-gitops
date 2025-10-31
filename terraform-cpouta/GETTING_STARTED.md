# Getting Started with OpenStack/cPouta k0s Deployment

Complete beginner-friendly guide to deploying your k0s cluster on CSC's cPouta.

---

## Part 1: Understanding the Tools

### What is OpenTofu/Terraform?

**Infrastructure as Code (IaC) tool** that:
- Uses `.tf` files to define infrastructure
- Works with multiple cloud providers (AWS, Azure, DigitalOcean, **OpenStack**)
- Same tool, different provider = different cloud resources

### What is OpenStack?

**Open-source cloud platform** that cPouta runs on:
- CSC's cPouta = OpenStack cloud in Finland
- Provides: VMs, storage, networking, etc.
- Accessed via: API, CLI, or Web dashboard

### The Workflow

```
Write .tf files → tofu init → tofu plan → tofu apply → Infrastructure created!
      ↓              ↓            ↓           ↓
   Define      Download     Preview      Create
   resources   provider     changes      resources
```

**Yes, OpenStack uses `.tf` files** - same format as DigitalOcean!

---

## Part 2: Install Required Tools

### 1. Install OpenTofu (Recommended) or Terraform

```bash
# OpenTofu (fully open source, recommended)
brew install opentofu

# Verify
tofu version
# Expected: OpenTofu v1.x.x

# Alternative: Terraform (if you prefer)
brew install terraform
terraform version
```

**Why OpenTofu?**
- Fully open-source (Terraform changed licensing in 2023)
- Drop-in replacement for Terraform
- Better for this use case ✅

### 2. Install OpenStack CLI

```bash
# Install via Homebrew
brew install openstackclient

# Verify
openstack --version
# Expected: openstack 6.x.x
```

**Why OpenStack CLI?**
- Discover available resources (networks, images, flavors)
- Debug issues
- Manage resources manually if needed

### 3. Verify SSH Key

```bash
# Check if you have SSH keys
ls -la ~/.ssh/id_rsa*

# If not, generate new ones
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
# Press Enter for all prompts (default settings)
```

---

## Part 3: CSC/cPouta Setup

### 1. Get CSC Account Access

If you don't have access:
1. Go to https://my.csc.fi
2. Register or log in with Haka (Finnish university federation)
3. Request cPouta project access
4. Wait for approval from CSC

### 2. Access cPouta Dashboard

```
URL: https://pouta.csc.fi
Login: Your CSC credentials
```

### 3. Download OpenRC File

**What is OpenRC?** Authentication file with your project credentials.

**How to download:**
1. Log in to https://pouta.csc.fi
2. Go to **Project → API Access** (left sidebar)
3. Click **Download OpenStack RC File** button
4. Save as: `project_XXXXXX-openrc.sh` (your project number)

**Move to safe location:**
```bash
# Create a directory for cloud credentials
mkdir -p ~/cloud-credentials
mv ~/Downloads/project_*-openrc.sh ~/cloud-credentials/

# Make it executable
chmod +x ~/cloud-credentials/project_*-openrc.sh
```

### 4. Source OpenRC File (Authenticate)

**IMPORTANT:** Do this **before every terminal session**!

```bash
# Navigate to credentials directory
cd ~/cloud-credentials

# Source the file
source project_XXXXXX-openrc.sh

# Enter your CSC password when prompted
```

This sets environment variables:
```bash
# Verify authentication
env | grep OS_

# You should see:
# OS_AUTH_URL=https://pouta.csc.fi:5001/v3
# OS_PROJECT_ID=...
# OS_PROJECT_NAME=...
# OS_USERNAME=...
# OS_PASSWORD=...
# etc.
```

### 5. Test Authentication

```bash
# List servers (should be empty or show existing VMs)
openstack server list

# If successful, you're authenticated! ✅
# If error, check password and re-source OpenRC file
```

---

## Part 4: Discover Your Resources

Before deploying, you need to find:
- Your project network name
- Available images
- Available flavors

### 1. Find Your Network

```bash
openstack network list
```

**Expected output:**
```
+--------------------------------------+------------------+
| ID                                   | Name             |
+--------------------------------------+------------------+
| xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   | public           |
| yyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   | project_2011111  | ← YOUR PROJECT NETWORK
+--------------------------------------+------------------+
```

**Note:** Your project network is named `project_XXXXXXX` (your project number).

### 2. List Available Images

```bash
openstack image list | grep -i ubuntu
```

**Common images:**
- Ubuntu-24.04 ✅ (recommended)
- Ubuntu-22.04
- Ubuntu-20.04
- CentOS-7
- RockyLinux-8

### 3. List Available Flavors

```bash
openstack flavor list
```

**Standard flavors for k0s:**

| Flavor | vCPU | RAM | Disk | Best For |
|--------|------|-----|------|----------|
| standard.tiny | 1 | 1GB | 80GB | Testing only |
| standard.small | 2 | 2GB | 80GB | Minimal k0s |
| **standard.medium** | 3 | 4GB | 80GB | **k0s workers ✅** |
| **standard.large** | 4 | 8GB | 80GB | **k0s controller ✅** |
| standard.xlarge | 6 | 15GB | 80GB | Heavy workloads |

**Recommendation:** Use `standard.medium` for workers, `standard.large` for controller.

---

## Part 5: Configure and Deploy

### 1. Navigate to terraform-cpouta

```bash
cd ~/PersonalCloud/terraform-cpouta
```

### 2. Create Configuration File

```bash
# Copy example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Minimum required configuration:**

```hcl
# Update this with YOUR project network from Step 4.1
network_name = "project_2011111"  # ← CHANGE THIS!

# Recommended flavors
image_name = "Ubuntu-24.04"
controller_flavor = "standard.large"   # 4 vCPU, 8GB RAM
worker_flavor = "standard.medium"      # 3 vCPU, 4GB RAM
worker_count = 4

# SSH settings (usually don't need to change)
ssh_public_key_path = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
ssh_user = "ubuntu"
```

### 3. Initialize OpenTofu

```bash
tofu init
```

**What this does:**
- Downloads OpenStack provider (version 3.3.2)
- Creates `.terraform/` directory
- Prepares backend

**Expected output:**
```
Initializing the backend...
Initializing provider plugins...
- Installing terraform-provider-openstack/openstack v3.3.2...
OpenTofu has been successfully initialized!
```

### 4. Preview Changes

```bash
tofu plan
```

**What this does:**
- Shows what will be created
- No actual changes yet
- Review before applying

**Expected resources (should show ~35 resources):**
- 5 compute instances
- 5 floating IPs
- 4 volumes (100GB each)
- 6 security groups + ~15 rules
- 1 SSH keypair
- Volume attachments and provisioners

### 5. Deploy Infrastructure

```bash
tofu apply
```

**What this does:**
1. Creates security groups
2. Uploads SSH key
3. Creates instances (controller + 4 workers)
4. Allocates floating IPs
5. Creates and attaches volumes
6. SSHs into workers to mount volumes
7. Generates `hosts.txt`

**Time:** ~5-10 minutes

**Confirmation prompt:**
```
Do you want to perform these actions?
  OpenTofu will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes  ← Type this
```

### 6. Monitor Progress

You'll see output like:
```
openstack_networking_secgroup_v2.ssh: Creating...
openstack_networking_secgroup_v2.ssh: Creation complete after 2s
openstack_compute_instance_v2.controller: Creating...
...
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.

Outputs:

controller_public_ip = "86.50.XXX.XXX"
worker_public_ips = [
  "86.50.XXX.XXX",
  "86.50.XXX.XXX",
  ...
]
```

---

## Part 6: Access Your Cluster

### 1. Add Hosts to /etc/hosts

```bash
# View generated hosts
cat hosts.txt

# Add to /etc/hosts (requires sudo)
sudo sh -c 'cat hosts.txt >> /etc/hosts'

# Verify
tail /etc/hosts
```

### 2. SSH to Nodes

```bash
# Controller
ssh ubuntu@k0s-controller

# Worker
ssh ubuntu@k0s-worker-1

# Exit
exit
```

### 3. Verify Volumes

```bash
# Check all workers have volumes mounted
for i in {1..4}; do
  echo "Worker $i:"
  ssh ubuntu@k0s-worker-$i "df -h /var/lib/k0s"
done
```

**Expected output:**
```
Worker 1:
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb         98G  24M   93G   1% /var/lib/k0s
...
```

### 4. Get All Outputs

```bash
# View all outputs
tofu output

# Get specific output
tofu output controller_public_ip
tofu output -json worker_public_ips

# Export for k0sctl
tofu output -json k0sctl_hosts > k0sctl-hosts.json
```

---

## Part 7: Next Steps

### 1. Deploy k0s with k0sctl

You now have infrastructure ready for k0s deployment!

**Update your k0sctl.yaml:**
```yaml
spec:
  hosts:
  - ssh:
      address: <controller_public_ip>
      user: ubuntu  # Changed from 'root'
      keyPath: ~/.ssh/id_rsa
    role: controller

  - ssh:
      address: <worker_public_ip_1>
      user: ubuntu  # Changed from 'root'
      keyPath: ~/.ssh/id_rsa
    role: worker
    # ... repeat for all workers
```

### 2. Verify Infrastructure

```bash
# OpenStack CLI
openstack server list
openstack volume list
openstack floating ip list

# OpenTofu
tofu show
tofu state list
```

---

## Troubleshooting

### "Authentication failed"

```bash
# Re-source OpenRC file
source ~/cloud-credentials/project_*-openrc.sh

# Verify environment
env | grep OS_AUTH_URL
openstack server list
```

### "Network not found"

```bash
# List networks again
openstack network list

# Copy EXACT name (case-sensitive)
# Update terraform.tfvars
```

### "Quota exceeded"

Check your project quota:
```bash
openstack quota show
```

Contact CSC if you need more resources: servicedesk@csc.fi

### SSH connection fails

```bash
# Check floating IPs are attached
openstack server show k0s-controller | grep addresses

# Check security group
openstack security group rule list k0s-cluster-ssh

# Try with verbose
ssh -v ubuntu@k0s-controller
```

### Volume not mounted

```bash
# SSH to worker
ssh ubuntu@k0s-worker-1

# Check block devices
lsblk

# Check mount
df -h | grep k0s

# Check fstab
cat /etc/fstab | grep k0s

# Manually mount if needed
sudo mount -a
```

---

## Common Commands Cheat Sheet

### Authentication
```bash
# Authenticate (do this every new terminal session)
source ~/cloud-credentials/project_*-openrc.sh

# Verify
openstack server list
```

### OpenTofu Workflow
```bash
tofu init       # Initialize (first time only)
tofu plan       # Preview changes
tofu apply      # Create/update infrastructure
tofu destroy    # Delete everything
tofu output     # Show outputs
tofu state list # List managed resources
```

### OpenStack CLI
```bash
openstack server list              # List VMs
openstack server show <name>       # Show VM details
openstack volume list              # List volumes
openstack floating ip list         # List floating IPs
openstack security group list      # List security groups
openstack image list | grep Ubuntu # Find images
openstack flavor list              # List VM sizes
openstack network list             # List networks
```

### SSH
```bash
ssh ubuntu@k0s-controller          # Controller
ssh ubuntu@k0s-worker-1            # Worker
ssh ubuntu@86.50.XXX.XXX           # Direct IP
```

---

## File Structure

```
terraform-cpouta/
├── main.tf                    # Infrastructure definition (OpenStack resources)
├── variables.tf               # Variable declarations
├── terraform.tfvars           # YOUR VALUES (git-ignored, contains your config)
├── terraform.tfvars.example   # Template
├── .gitignore                 # Ignores sensitive files
├── README.md                  # Full documentation
├── QUICKSTART.md              # 5-minute guide
└── GETTING_STARTED.md         # This file

# Generated after 'tofu apply':
├── .terraform/                # Provider plugins (auto-generated)
├── .terraform.lock.hcl        # Provider version lock
├── terraform.tfstate          # Current state (IMPORTANT!)
└── hosts.txt                  # Generated hosts entries
```

---

## Cost Management

### Billing Units (BU)

cPouta uses Billing Units. Your deployment costs approximately:

**Monthly estimate:**
- Controller (standard.large): 4 vCPU × 24h × 30d = ~2,880 BU
- Workers (4 × standard.medium): 4 × 3 vCPU × 24h × 30d = ~8,640 BU
- Volumes (400 GB): ~40 BU
- Floating IPs: ~5 BU

**Total: ~11,565 BU/month**

### Check Your Usage

```bash
# View project resources
openstack server list
openstack volume list

# Check project limits
openstack quota show
```

### Save Costs

- **Stop unused VMs**: `openstack server stop <name>` (still charges for storage)
- **Delete when not needed**: `tofu destroy`
- **Use smaller flavors**: Change to `standard.small` for testing

---

## Additional Resources

### CSC Documentation
- [cPouta User Guide](https://docs.csc.fi/cloud/pouta/)
- [VM Flavors and Billing](https://docs.csc.fi/cloud/pouta/vm-flavors-and-billing/)
- [cPouta Images](https://docs.csc.fi/cloud/pouta/images/)

### OpenTofu
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [OpenTofu vs Terraform](https://opentofu.org/docs/intro/migration/)

### OpenStack Provider
- [Provider Documentation](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [CSC Terraform Example](https://github.com/CSCfi/terraform-openstack-example)

### Support
- **CSC Service Desk**: servicedesk@csc.fi
- **cPouta Status**: https://research.csc.fi/status

---

## Next: Deploy k0s

Once your infrastructure is ready, proceed to:
1. Update k0sctl.yaml with floating IPs
2. Deploy k0s cluster
3. Deploy ArgoCD and your applications

Your cPouta infrastructure is now ready! 🚀
