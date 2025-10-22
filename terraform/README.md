# Terraform AWS Graviton (ARM64) Infrastructure

Provisions ARM-based EC2 instances for k0s cluster.

## Prerequisites

1. **AWS CLI configured:**

   ```bash
   aws configure
   ```

2. **SSH key pair in AWS:**

   ```bash
   aws ec2 create-key-pair --key-name k0s-key --query 'KeyMaterial' --output text > ~/.ssh/k0s-key.pem
   chmod 400 ~/.ssh/k0s-key.pem
   ```

3. **Terraform installed:**
   ```bash
   brew install terraform
   ```

## Usage

1. **Copy example config:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars:**

   ```bash
   aws_region    = "us-east-1"
   instance_type = "t4g.small"
   ssh_key_name  = "k0s-key"
   ```

3. **Initialize Terraform:**

   ```bash
   terraform init
   ```

4. **Plan:**

   ```bash
   terraform plan
   ```

5. **Apply:**

   ```bash
   terraform apply
   ```

6. **Get outputs:**

   ```bash
   terraform output
   ```

7. **Add to k0sctl.yaml:**
   Use the `instance_ip` output in your k0sctl configuration.

## Destroy

```bash
terraform destroy
```

## Instance Types

- `t4g.small` - 2 vCPU, 2GB RAM - Free tier eligible until Dec 2025
- `t4g.medium` - 2 vCPU, 4GB RAM - ~$30/mo
- `t4g.large` - 2 vCPU, 8GB RAM - ~$60/mo
- `c7g.medium` - 1 vCPU, 2GB RAM - Compute optimized
