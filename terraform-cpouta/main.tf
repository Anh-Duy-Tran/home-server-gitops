terraform {
  required_version = ">= 1.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.3.2"
    }
  }
}

# Provider configuration - uses OpenRC environment variables
# Source your OpenRC file before running: source project_XXXXXX-openrc.sh
provider "openstack" {
  # Authentication via environment variables from OpenRC file:
  # OS_AUTH_URL, OS_PROJECT_ID, OS_PROJECT_NAME, OS_USER_DOMAIN_NAME, OS_USERNAME, OS_PASSWORD, OS_REGION_NAME
}

# Data sources to lookup existing resources
data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

data "openstack_networking_network_v2" "public" {
  name = "public"
}

data "openstack_networking_network_v2" "private" {
  name = var.network_name
}

# SSH Key Pair
resource "openstack_compute_keypair_v2" "k0s" {
  name       = "k0s-cluster-key"
  public_key = file(var.ssh_public_key_path)
}

# Security Groups

# Security group for SSH access
resource "openstack_networking_secgroup_v2" "ssh" {
  name        = "k0s-cluster-ssh"
  description = "Allow SSH access to k0s cluster nodes"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ipv4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ssh.id
}

# Security group for Kubernetes API
resource "openstack_networking_secgroup_v2" "k8s_api" {
  name        = "k0s-cluster-api"
  description = "Allow Kubernetes API access"
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_ipv4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_api.id
}

# Security group for HTTP/HTTPS ingress
resource "openstack_networking_secgroup_v2" "web" {
  name        = "k0s-cluster-web"
  description = "Allow HTTP and HTTPS access"
}

resource "openstack_networking_secgroup_rule_v2" "http_ipv4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "https_ipv4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

# Security group for Konnectivity
resource "openstack_networking_secgroup_v2" "konnectivity" {
  name        = "k0s-cluster-konnectivity"
  description = "Allow Konnectivity ports"
}

resource "openstack_networking_secgroup_rule_v2" "konnectivity_8132" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8132
  port_range_max    = 8132
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.konnectivity.id
}

resource "openstack_networking_secgroup_rule_v2" "konnectivity_8133" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8133
  port_range_max    = 8133
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.konnectivity.id
}

# Security group for inter-cluster communication
resource "openstack_networking_secgroup_v2" "cluster_internal" {
  name        = "k0s-cluster-internal"
  description = "Allow all traffic between cluster nodes"
}

# Allow all TCP traffic from cluster nodes
resource "openstack_networking_secgroup_rule_v2" "cluster_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_group_id   = openstack_networking_secgroup_v2.cluster_internal.id
  security_group_id = openstack_networking_secgroup_v2.cluster_internal.id
}

# Allow all UDP traffic from cluster nodes
resource "openstack_networking_secgroup_rule_v2" "cluster_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_group_id   = openstack_networking_secgroup_v2.cluster_internal.id
  security_group_id = openstack_networking_secgroup_v2.cluster_internal.id
}

# Allow ICMP from cluster nodes (for ping and networking diagnostics)
resource "openstack_networking_secgroup_rule_v2" "cluster_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_group_id   = openstack_networking_secgroup_v2.cluster_internal.id
  security_group_id = openstack_networking_secgroup_v2.cluster_internal.id
}

# Volumes for workers (100GB each)
resource "openstack_blockstorage_volume_v3" "worker_storage" {
  count       = var.worker_count
  name        = "k0s-worker-${count.index + 1}-storage"
  size        = 100
  description = "Storage volume for k0s worker ${count.index + 1}"
}

# Controller node
resource "openstack_compute_instance_v2" "controller" {
  name        = "k0s-controller"
  image_id    = data.openstack_images_image_v2.ubuntu.id
  flavor_name = var.controller_flavor
  key_pair    = openstack_compute_keypair_v2.k0s.name

  security_groups = [
    openstack_networking_secgroup_v2.ssh.name,
    openstack_networking_secgroup_v2.k8s_api.name,
    openstack_networking_secgroup_v2.web.name,
    openstack_networking_secgroup_v2.konnectivity.name,
    openstack_networking_secgroup_v2.cluster_internal.name,
  ]

  network {
    name = var.network_name
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Basic setup
    apt-get update
    apt-get install -y curl wget

    # Disable swap
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  EOF
}

# Floating IP for controller
resource "openstack_networking_floatingip_v2" "controller" {
  pool = "public"
}

resource "openstack_compute_floatingip_associate_v2" "controller" {
  floating_ip = openstack_networking_floatingip_v2.controller.address
  instance_id = openstack_compute_instance_v2.controller.id
}

# Worker nodes
resource "openstack_compute_instance_v2" "workers" {
  count       = var.worker_count
  name        = "k0s-worker-${count.index + 1}"
  image_id    = data.openstack_images_image_v2.ubuntu.id
  flavor_name = var.worker_flavor
  key_pair    = openstack_compute_keypair_v2.k0s.name

  security_groups = [
    openstack_networking_secgroup_v2.ssh.name,
    openstack_networking_secgroup_v2.web.name,
    openstack_networking_secgroup_v2.cluster_internal.name,
  ]

  network {
    name = var.network_name
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Basic setup
    apt-get update
    apt-get install -y curl wget

    # Disable swap
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  EOF
}

# Floating IPs for workers
resource "openstack_networking_floatingip_v2" "workers" {
  count = var.worker_count
  pool  = "public"
}

resource "openstack_compute_floatingip_associate_v2" "workers" {
  count       = var.worker_count
  floating_ip = openstack_networking_floatingip_v2.workers[count.index].address
  instance_id = openstack_compute_instance_v2.workers[count.index].id
}

# Attach volumes to workers
resource "openstack_compute_volume_attach_v2" "worker_storage" {
  count       = var.worker_count
  instance_id = openstack_compute_instance_v2.workers[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.worker_storage[count.index].id
}

# Configure volumes to mount at /var/lib/k0s
resource "null_resource" "configure_volumes" {
  count = var.worker_count

  depends_on = [
    openstack_compute_volume_attach_v2.worker_storage,
    openstack_compute_floatingip_associate_v2.workers
  ]

  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = openstack_networking_floatingip_v2.workers[count.index].address
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 30", # Wait for volume to be attached and system to stabilize
      "sudo mkdir -p /var/lib/k0s",
      # Find the device (usually /dev/vdb for first additional volume)
      "DEVICE=$(lsblk -o NAME,TYPE,SIZE -d -n | grep disk | awk 'NR==2{print \"/dev/\"$1}')",
      "echo \"Found device: $DEVICE\"",
      # Create filesystem if not exists
      "sudo mkfs.ext4 -F $DEVICE || true",
      # Mount the volume
      "sudo mount -o defaults,noatime $DEVICE /var/lib/k0s",
      # Add to fstab for persistence
      "DEVICE_UUID=$(sudo blkid -s UUID -o value $DEVICE)",
      "echo \"UUID=$DEVICE_UUID /var/lib/k0s ext4 defaults,nofail,noatime 0 0\" | sudo tee -a /etc/fstab",
      "df -h /var/lib/k0s"
    ]
  }
}

# Generate hosts file entries
resource "local_file" "hosts_entries" {
  filename = "${path.module}/hosts.txt"
  content  = <<-EOT
# k0s Cluster Hosts
${openstack_networking_floatingip_v2.controller.address}    k0s-controller
%{for idx, worker in openstack_compute_instance_v2.workers~}
${openstack_networking_floatingip_v2.workers[idx].address}    ${worker.name}
%{endfor~}
  EOT
}

# Outputs
output "controller_public_ip" {
  value       = openstack_networking_floatingip_v2.controller.address
  description = "Public IP address of the controller node"
}

output "controller_private_ip" {
  value       = openstack_compute_instance_v2.controller.access_ip_v4
  description = "Private IP address of the controller node"
}

output "worker_public_ips" {
  value       = openstack_networking_floatingip_v2.workers[*].address
  description = "Public IP addresses of worker nodes"
}

output "worker_private_ips" {
  value       = openstack_compute_instance_v2.workers[*].access_ip_v4
  description = "Private IP addresses of worker nodes"
}

output "ssh_controller" {
  value       = "ssh ${var.ssh_user}@${openstack_networking_floatingip_v2.controller.address}"
  description = "SSH command for controller node"
}

output "ssh_workers" {
  value       = [for ip in openstack_networking_floatingip_v2.workers[*].address : "ssh ${var.ssh_user}@${ip}"]
  description = "SSH commands for worker nodes"
}

output "k0sctl_hosts" {
  value = {
    controller = {
      role = "controller"
      ssh = {
        address = openstack_networking_floatingip_v2.controller.address
        user    = var.ssh_user
      }
    }
    workers = [for idx, ip in openstack_networking_floatingip_v2.workers[*].address : {
      role = "worker"
      ssh = {
        address = ip
        user    = var.ssh_user
      }
    }]
  }
  description = "k0sctl hosts configuration"
}
