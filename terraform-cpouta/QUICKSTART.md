# Quick Start Guide - OpenStack/cPouta k0s Cluster

Fast track to deploying your k0s cluster on CSC's cPouta OpenStack cloud.

## Prerequisites Checklist

- [ ] CSC account with cPouta access
- [ ] Downloaded OpenRC file from cPouta dashboard
- [ ] OpenTofu installed (`brew install opentofu`)
- [ ] OpenStack CLI installed (`brew install openstackclient`)
- [ ] SSH key pair generated (`ssh-keygen -t rsa -b 4096`)

## 5-Minute Setup

### 1. Authenticate with OpenStack

```bash
# Download your OpenRC file from https://pouta.csc.fi (API Access page)
# Then source it:
source project_XXXXXX-openrc.sh
# Enter your CSC password
```

### 2. Discover Your Resources

```bash
# Find your network name
openstack network list
# Look for: project_XXXXXXX

# Check available images
openstack image list | grep Ubuntu
# Recommended: Ubuntu-24.04

# Check flavors (VM sizes)
openstack flavor list | grep standard
# Recommended: standard.medium (2 vCPU, 8GB RAM)
```

### 3. Configure

```bash
cd terraform-cpouta

# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Minimum required changes:**

```hcl
network_name = "project_2011111"  # Your actual project network from step 2
```

### 4. Deploy

```bash
# Initialize
tofu init

# Preview changes
tofu plan

# Deploy (takes ~5-10 minutes)
tofu apply
# Type: yes
```

### 5. Access

```bash
# Add hosts to /etc/hosts
sudo sh -c 'cat hosts.txt >> /etc/hosts'

# SSH to controller
ssh ubuntu@k0s-controller

# Get all outputs
tofu output
```

## What Gets Created

- ✅ 1 controller node (standard.medium)
- ✅ 4 worker nodes (standard.medium)
- ✅ 5 floating IPs (public access)
- ✅ 4 × 100GB volumes (mounted at /var/lib/k0s)
- ✅ 6 security groups (firewall rules)
- ✅ SSH keypair uploaded to OpenStack

## Next Steps

1. **Deploy k0s**: Use k0sctl with the generated host configuration

   ```bash
   tofu output -json k0sctl_hosts > k0sctl-hosts.json
   ```

2. **Verify volumes**:

   ```bash
   ssh ubuntu@k0s-worker-1 "df -h /var/lib/k0s"
   ```

3. **Update your k0sctl.yaml**: Use the floating IPs and change SSH user to `ubuntu`

## Common Issues

### Can't authenticate?

```bash
# Verify environment variables
env | grep OS_

# Re-source OpenRC file
source project_XXXXXX-openrc.sh
```

### Network not found?

```bash
# List networks and copy exact name
openstack network list
# Update terraform.tfvars with exact name
```

### SSH fails?

```bash
# Check floating IPs are attached
openstack server list

# Verify security group
openstack security group rule list k0s-cluster-ssh
```

## Cleanup

```bash
# Destroy everything
tofu destroy
# Type: yes

# Remove from /etc/hosts
sudo nano /etc/hosts
# Delete the lines from hosts.txt
```

## Cost Estimate

Approximate monthly cost: **~5,800 Billing Units (BU)**

- Compute: 5 × standard.medium = ~5,760 BU/month
- Storage: 400GB volumes = ~40 BU/month
- Floating IPs: ~5 BU/month

## Need Help?

- 📖 Full README: [README.md](README.md)
- 🐛 CSC Support: servicedesk@csc.fi
- 📚 cPouta Docs: https://docs.csc.fi/cloud/pouta/
