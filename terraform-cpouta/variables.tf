variable "image_name" {
  description = "OpenStack image name (use 'openstack image list' to see available images)"
  type        = string
  default     = "Ubuntu-24.04"
}

variable "network_name" {
  description = "OpenStack network name (use 'openstack network list' to see available networks)"
  type        = string
  default     = "project_2011111" # Replace with your project network
}

variable "controller_flavor" {
  description = "Flavor (size) for controller node (use 'openstack flavor list')"
  type        = string
  default     = "standard.medium" # 2 vCPU, 8GB RAM
}

variable "worker_flavor" {
  description = "Flavor (size) for worker nodes (use 'openstack flavor list')"
  type        = string
  default     = "standard.medium" # 2 vCPU, 8GB RAM
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 4
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "SSH user for the Ubuntu image (usually 'ubuntu' or 'cloud-user')"
  type        = string
  default     = "ubuntu"
}
