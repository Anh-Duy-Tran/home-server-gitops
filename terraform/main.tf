terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Ubuntu ARM64 AMI
data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group
resource "aws_security_group" "k0s_node" {
  name        = "k0s-node-sg"
  description = "Security group for k0s nodes"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # k0s API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Konnectivity
  ingress {
    from_port   = 8132
    to_port     = 8133
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal cluster communication
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k0s-node-sg"
  }
}

# EC2 Instance - ARM64 Graviton
resource "aws_instance" "k0s_arm_node" {
  ami           = data.aws_ami.ubuntu_arm64.id
  instance_type = var.instance_type

  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.k0s_node.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "k0s-arm-worker"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y curl wget
              EOF
}

output "instance_ip" {
  value = aws_instance.k0s_arm_node.public_ip
}

output "instance_id" {
  value = aws_instance.k0s_arm_node.id
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_instance.k0s_arm_node.public_ip}"
}
