########################################
# Terraform & Provider Configuration
########################################
terraform {
  required_version = ">= 1.3.0"

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

########################################
# Variables
########################################
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "project_name" {
  type    = string
  default = "devops-webapp"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC to deploy into (e.g., vpc-xxxxxxxx)."
  default     = "vpc-0bb695c41dc9db0a4"
}

variable "subnet_id" {
  type        = string
  description = "Optional: Subnet to use. If empty, the first available subnet in the VPC will be used."
  default     = ""
}

variable "reuse_existing_sg" {
  type    = bool
  default = true
}

variable "existing_sg_name" {
  type    = string
  default = "web-server-sg"
}

variable "keypair_name" {
  type    = string
  default = "deploy-key"
}

variable "ansible_user" {
  type    = string
  default = "ubuntu"
}

variable "apache_instance_count" {
  type    = number
  default = 2
}

variable "nginx_instance_count" {
  type    = number
  default = 2
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

########################################
# Locals
########################################
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

########################################
# Data Sources
########################################

# Selected VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# All subnets in the VPC (we'll choose the first if subnet_id is not provided)
data "aws_subnets" "in_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Optionally reuse an existing security group by name in the same VPC
data "aws_security_group" "existing_web" {
  count = var.reuse_existing_sg ? 1 : 0

  filter {
    name   = "group-name"
    values = [var.existing_sg_name]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Ubuntu 22.04 LTS (Jammy) AMI - latest in region
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

########################################
# Derived Selections
########################################
# Choose the subnet: use provided subnet_id if given; else first subnet in the VPC.
locals {
  selected_subnet_id = var.subnet_id != "" ? var.subnet_id : (
    length(data.aws_subnets.in_vpc.ids) > 0 ? data.aws_subnets.in_vpc.ids[0] : ""
  )
}

########################################
# Security Group (create new if not reusing)
########################################
resource "aws_security_group" "web" {
  count       = var.reuse_existing_sg ? 0 : 1
  name        = "${var.project_name}-web-sg-${var.environment}"
  description = "Web security group for ${var.project_name} (${var.environment})"
  vpc_id      = data.aws_vpc.selected.id

  # Allow HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # (Optional) Allow SSH - restrict CIDR in production
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-sg-${var.environment}"
  })
}

# Helper local to reference the chosen SG ID
locals {
  web_sg_id = var.reuse_existing_sg ? data.aws_security_group.existing_web[0].id : aws_security_group.web[0].id
}

########################################
# EC2 Instances - Apache
########################################
resource "aws_instance" "apache" {
  count                       = var.apache_instance_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.selected_subnet_id
  vpc_security_group_ids      = [local.web_sg_id]
  key_name                    = var.keypair_name
  associate_public_ip_address = true

  # Optional Apache bootstrap
  # user_data = <<-EOT
  #   #!/bin/bash
  #   apt-get update -y
  #   apt-get install -y apache2
  #   systemctl enable apache2
  #   systemctl start apache2
  # EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-apache-${count.index + 1}-${var.environment}"
    Role = "apache"
  })
}

########################################
# EC2 Instances - Nginx
########################################
resource "aws_instance" "nginx" {
  count                       = var.nginx_instance_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.selected_subnet_id
  vpc_security_group_ids      = [local.web_sg_id]
  key_name                    = var.keypair_name
  associate_public_ip_address = true

  # Optional Nginx bootstrap
  # user_data = <<-EOT
  #   #!/bin/bash
  #   apt-get update -y
  #   apt-get install -y nginx
  #   systemctl enable nginx
  #   systemctl start nginx
  # EOT

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nginx-${count.index + 1}-${var.environment}"
    Role = "nginx"
  })
}

########################################
# Outputs
########################################
output "subnet_id_used" {
  description = "The subnet ID used for EC2 instances."
  value       = local.selected_subnet_id
}

output "security_group_id" {
  description = "ID of the security group used by instances."
  value       = local.web_sg_id
}

output "apache_public_ips" {
  description = "Public IPs of Apache instances."
  value       = [for i in aws_instance.apache : i.public_ip]
}

output "nginx_public_ips" {
  description = "Public IPs of Nginx instances."
  value       = [for i in aws_instance.nginx : i.public_ip]
}
