variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "fra1" # Frankfurt
}

variable "controller_size" {
  description = "Droplet size for controller node"
  type        = string
  default     = "g-2vcpu-8gb" # General Purpose: 2 vCPU, 8GB RAM
}

variable "worker_size" {
  description = "Droplet size for worker nodes"
  type        = string
  default     = "g-2vcpu-8gb" # General Purpose: 2 vCPU, 8GB RAM
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
