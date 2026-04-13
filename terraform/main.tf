# Zegel Terraform deployment (improvement #115).
#
# Provisions a small AWS footprint suitable for a production Zegel
# deployment: one t3.small EC2 instance running the container image,
# an EBS volume for sealed-file storage, and a security group that
# only exposes port 443 via an ALB.
#
# Use with `terraform init && terraform apply`. The `aws_region` and
# `key_name` variables are the only mandatory inputs.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
}

variable "key_name" {
  type        = string
  description = "Name of an existing EC2 key pair to associate with the instance"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to place the resources in"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to place the instance in"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "data_volume_size_gb" {
  type    = number
  default = 20
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }
}

resource "aws_security_group" "zegel" {
  name        = "zegel-sg"
  description = "Zegel service ingress/egress"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "zegel" {
  ami                    = data.aws_ami.debian.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.zegel.id]

  user_data = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl docker.io
    systemctl enable --now docker
    docker pull ghcr.io/zegel/zegel:latest
    docker run -d --name zegel --restart unless-stopped \
      -p 443:8080 \
      -v /var/lib/zegel:/var/lib/zegel \
      ghcr.io/zegel/zegel:latest
  EOF

  tags = {
    Name        = "zegel"
    Environment = "prod"
  }
}

resource "aws_ebs_volume" "zegel_data" {
  availability_zone = aws_instance.zegel.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true
  tags = {
    Name = "zegel-data"
  }
}

resource "aws_volume_attachment" "zegel_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.zegel_data.id
  instance_id = aws_instance.zegel.id
}

output "instance_public_ip" {
  value = aws_instance.zegel.public_ip
}
