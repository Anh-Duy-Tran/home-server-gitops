variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type (Graviton ARM64)"
  type        = string
  default     = "t4g.small" # Free tier eligible until Dec 2025
  # Other options: t4g.medium, t4g.large, c7g.medium, etc.
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
}
