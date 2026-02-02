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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
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

# === Key pair management ===
variable "keypair_name" {
  type    = string
  default = "deploy-key"
}

# If true, Terraform will create/manage the AWS key pair.
variable "create_key_pair" {
  type    = bool
  default = true
}

# If you already have a public key (OpenSSH format), set it here (optional).
# When set (and create_key_pair = true), Terraform will create the AWS key pair from this public key.
# When empty and create_key_pair = true, Terraform will GENERATE a new key pair and save the private key PEM locally (0600).
variable "public_key_openssh" {
  type    = string
  default = ""
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
# Key Pair Management
########################################

# Generate a new RSA key only if:
#  - create_key_pair = true
#  - public_key_openssh is NOT provided (we will generate a new key then)
resource "tls_private_key" "generated" {
  count     = var.create_key_pair && var.public_key_openssh == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create the AWS Key Pair from either provided public key or generated one
resource "aws_key_pair" "this" {
  count     = var.create_key_pair ? 1 : 0
  key_name  = var.keypair_name
  public_key = var.public_key_openssh != "" ?
    var.public_key_openssh :
    tls_private_key.generated[0].public_key_openssh
}

# If we generated a key (no public key provided), write the private key to a local file (0600)
resource "local_file" "generated_pem" {
  count           = var.create_key_pair && var.public_key_openssh == "" ? 1 : 0
  filename        = "${path.module}/generated_${var.keypair_name}.pem"
  content         = tls_private_key.generated[0].private_key_pem
  file_permission = "0600"
}

# Decide which key name instances should use
locals {
  selected_key_name = var.create_key_pair ? aws_key_pair.this[0].key_name : var.keypair_name
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
  key_name                    = local.selected_key_name
  associate_public_ip_address = true

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
  key_name                    = local.selected_key_name
  associate_public_ip_address = true

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

# Useful outputs for Jenkins/Ansible
output "key_name_used" {
  description = "Key pair name used by instances."
  value       = local.selected_key_name
}

output "generated_private_key_path" {
  description = "Path to the generated PEM (if Terraform generated a key). Empty otherwise."
  value       = var.create_key_pair && var.public_key_openssh == "" ? local_file.generated_pem[0].filename : ""
  sensitive   = false
}

output "ansible_user" {
  description = "Default Ansible SSH user for the AMI."
  value       = var.ansible_user
}
