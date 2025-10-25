terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# SSH Key
resource "digitalocean_ssh_key" "k0s" {
  name       = "k0s-cluster-key"
  public_key = file(var.ssh_public_key_path)
}

# Firewall
resource "digitalocean_firewall" "k0s" {
  name = "k0s-cluster-fw"

  droplet_ids = concat(
    [digitalocean_droplet.controller.id],
    digitalocean_droplet.workers[*].id
  )

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Kubernetes API
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTP/HTTPS for ingress
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Konnectivity
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8132-8133"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all traffic between cluster nodes
  inbound_rule {
    protocol   = "tcp"
    port_range = "1-65535"
    source_droplet_ids = concat(
      [digitalocean_droplet.controller.id],
      digitalocean_droplet.workers[*].id
    )
  }

  inbound_rule {
    protocol   = "udp"
    port_range = "1-65535"
    source_droplet_ids = concat(
      [digitalocean_droplet.controller.id],
      digitalocean_droplet.workers[*].id
    )
  }

  # Allow all outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Volumes for workers (100GB each)
resource "digitalocean_volume" "worker_storage" {
  count  = var.worker_count
  region = var.region
  name   = "k0s-worker-${count.index + 1}-storage"
  size   = 100

  initial_filesystem_type = "ext4"
}

# Controller node
resource "digitalocean_droplet" "controller" {
  image    = "ubuntu-24-04-x64"
  name     = "k0s-controller"
  region   = var.region
  size     = var.controller_size
  ssh_keys = [digitalocean_ssh_key.k0s.fingerprint]

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

# Worker nodes
resource "digitalocean_droplet" "workers" {
  count    = var.worker_count
  image    = "ubuntu-24-04-x64"
  name     = "k0s-worker-${count.index + 1}"
  region   = var.region
  size     = var.worker_size
  ssh_keys = [digitalocean_ssh_key.k0s.fingerprint]

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

# Attach volumes to workers
resource "digitalocean_volume_attachment" "worker_storage" {
  count      = var.worker_count
  droplet_id = digitalocean_droplet.workers[count.index].id
  volume_id  = digitalocean_volume.worker_storage[count.index].id
}

# Configure volumes to mount at /var/lib/k0s
resource "null_resource" "configure_volumes" {
  count = var.worker_count

  depends_on = [digitalocean_volume_attachment.worker_storage]

  connection {
    type        = "ssh"
    user        = "root"
    host        = digitalocean_droplet.workers[count.index].ipv4_address
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 30", # Wait for volume to be attached
      "mkdir -p /var/lib/k0s",
      "mount -o discard,defaults,noatime /dev/disk/by-id/scsi-0DO_Volume_${digitalocean_volume.worker_storage[count.index].name} /var/lib/k0s",
      "echo '/dev/disk/by-id/scsi-0DO_Volume_${digitalocean_volume.worker_storage[count.index].name} /var/lib/k0s ext4 defaults,nofail,discard 0 0' | tee -a /etc/fstab",
      "df -h /var/lib/k0s"
    ]
  }
}

output "controller_ip" {
  value = digitalocean_droplet.controller.ipv4_address
}

output "worker_ips" {
  value = digitalocean_droplet.workers[*].ipv4_address
}

output "ssh_controller" {
  value = "ssh root@${digitalocean_droplet.controller.ipv4_address}"
}

output "ssh_workers" {
  value = [for ip in digitalocean_droplet.workers[*].ipv4_address : "ssh root@${ip}"]
}

output "k0sctl_hosts" {
  value = {
    controller = {
      role = "controller"
      ssh = {
        address = digitalocean_droplet.controller.ipv4_address
        user    = "root"
      }
    }
    workers = [for idx, ip in digitalocean_droplet.workers[*].ipv4_address : {
      role = "worker"
      ssh = {
        address = ip
        user    = "root"
      }
    }]
  }
}
