terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

############################
# Variables
############################
variable "aws_region" { type = string, default = "ap-south-1" }
variable "environment" { type = string, default = "production" }
variable "project_name" { type = string, default = "devops-webapp" }

# Existing VPC and subnet (leave subnet_id empty to auto-pick first in VPC)
variable "vpc_id" { type = string, default = "vpc-0bb695c41dc9db0a4" }
variable "subnet_id" { type = string, default = "" }

# Reuse an existing SG named 'web-server-sg' or create a new one
variable "reuse_existing_sg" { type = bool, default = true }
variable "existing_sg_name" { type = string, default = "web-server-sg" }

# Fixed keypair name (no random suffix required now)
variable "keypair_name" { type = string, default = "deploy-key" }

variable "ansible_user" { type = string, default = "ubuntu" }
variable "apache_instance_count" { type = number, default = 2 }
variable "nginx_instance_count" { type = number, default = 2 }
variable "instance_type" { type = string, default = "t3.micro" }

variable "ami_id" {
  type        = string
  default     = "ami-019715e0d74f695be"
  validation {
    condition     = length(var.ami_id) > 0 && can(regex("^ami-[0-9a-fA-F]{8,}$", var.ami_id))
    error_message = "Provide a valid AMI ID in your region."
  }
}

variable "jenkins_ip" {
  type        = string
  description = "Bare IPv4 only, e.g., 3.110.120.129"
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.jenkins_ip))
    error_message = "jenkins_ip must be a bare IPv4."
  }
}

############################
# Provider & Data
############################
provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "in_vpc" {
  filter { name = "vpc-id", values = [data.aws_vpc.selected.id] }
}

data "aws_security_group" "existing_web" {
  count = var.reuse_existing_sg ? 1 : 0
  filter { name = "group-name", values = [var.existing_sg_name] }
  filter { name = "vpc-id", values = [data.aws_vpc.selected.id] }
}

locals {
  selected_subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.in_vpc.ids[0]
}

############################
# (Optional) create SG if not reusing
############################
resource "random_id" "sg" {
  count       = var.reuse_existing_sg ? 0 : 1
  byte_length = 2
}

resource "aws_security_group" "web" {
  count       = var.reuse_existing_sg ? 0 : 1
  name_prefix = "web-server-sg-"
  description = "Security group for web servers"
  vpc_id      = data.aws_vpc.selected.id

  ingress { description = "HTTP";  from_port = 80;  to_port = 80;  protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { description = "HTTPS"; from_port = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { description = "SSH from Jenkins"; from_port = 22; to_port = 22; protocol = "tcp"; cidr_blocks = ["${var.jenkins_ip}/32"] }
  egress  { description = "All outbound"; from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }

  tags = {
    Name        = "web-server-sg-${try(random_id.sg[0].hex, "new")}"
    Environment = var.environment
    Project     = var.project_name
  }
}

locals {
  web_sg_id = var.reuse_existing_sg ? data.aws_security_group.existing_web[0].id : aws_security_group.web[0].id
}

############################
# Key pair (FIXED name) + local files
############################
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = var.keypair_name
  public_key = tls_private_key.web.public_key_openssh
  tags = {
    Name        = var.keypair_name
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "null_resource" "ensure_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../ansible-playbooks/inventory ${path.module}/../ansible-playbooks/keys"
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/../ansible-playbooks/keys/${var.keypair_name}.pem"
  file_permission = "0600"
  depends_on      = [null_resource.ensure_dirs]
}

resource "local_file" "public_key" {
  content         = tls_private_key.web.public_key_openssh
  filename        = "${path.module}/../ansible-playbooks/keys/${var.keypair_name}.pub"
  file_permission = "0644"
  depends_on      = [null_resource.ensure_dirs]
}

############################
# EC2 Instances
############################
resource "aws_instance" "apache" {
  count                       = var.apache_instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [local.web_sg_id]
  subnet_id                   = local.selected_subnet_id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get upgrade -y
                apt-get install -y apache2 python3 python3-pip
                systemctl enable apache2 && systemctl start apache2
                WEBROOT="/var/www/html"
              else
                yum update -y
                yum install -y httpd python3
                systemctl enable httpd && systemctl start httpd
                WEBROOT="/var/www/html"; [ -d "$WEBROOT" ] || WEBROOT="/usr/share/httpd/noindex"
              fi
              cat > "$WEBROOT/index.html" <<HTML
              <!doctype html><html><body style="font-family:Arial;text-align:center;padding:50px;background:#f0f0f0">
              <h1 style="color:#d62828">🔴 Apache Server ${count.index + 1}</h1><p>Ready for Ansible</p>
              </body></html>
HTML
              EOF

  tags = {
    Name        = "apache-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "apache"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_instance" "nginx" {
  count                       = var.nginx_instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [local.web_sg_id]
  subnet_id                   = local.selected_subnet_id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get upgrade -y
                apt-get install -y nginx python3 python3-pip
                systemctl enable nginx && systemctl start nginx
                WEBROOT="/var/www/html"; rm -f /var/www/html/index.nginx-debian.html || true
              else
                yum update -y
                amazon-linux-extras install -y nginx1 || yum install -y nginx
                systemctl enable nginx && systemctl start nginx
                WEBROOT="/usr/share/nginx/html"
              fi
              cat > "$WEBROOT/index.html" <<HTML
              <!doctype html><html><body style="font-family:Arial;text-align:center;padding:50px;background:#f0f0f0">
              <h1 style="color:#009688">🔵 Nginx Server ${count.index + 1}</h1><p>Ready for Ansible</p>
              </body></html>
HTML
              EOF

  tags = {
    Name        = "nginx-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "nginx"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle { create_before_destroy = true }
}

############################
# Dynamic Ansible Inventory (uses stable ../keys/current.pem)
############################
resource "local_file" "ansible_inventory" {
  content = join("\n", [
    "[apache]",
    length(aws_instance.apache) > 0 ? join("\n", aws_instance.apache[*].public_ip) : "",
    "",
    "[nginx]",
    length(aws_instance.nginx) > 0 ? join("\n", aws_instance.nginx[*].public_ip) : "",
    "",
    "[apache:vars]",
    "ansible_user=${var.ansible_user}",
    "ansible_ssh_private_key_file=../keys/current.pem",
    "ansible_python_interpreter=/usr/bin/python3",
    "",
    "[nginx:vars]",
    "ansible_user=${var.ansible_user}",
    "ansible_ssh_private_key_file=../keys/current.pem",
    "ansible_python_interpreter=/usr/bin/python3",
    ""
  ])

  filename   = "${path.module}/../ansible-playbooks/inventory/hosts.ini"
  depends_on = [null_resource.ensure_dirs, aws_instance.apache, aws_instance.nginx]
}

############################
# Outputs (absolute paths for Jenkins)
############################
output "effective_keypair_name" {
  value       = aws_key_pair.deployer.key_name
  description = "Fixed AWS key pair name"
}

output "generated_private_key_path" {
  value       = abspath(local_file.private_key.filename)
  description = "Absolute path to the generated private key (fixed name)"
  sensitive   = false
}

output "inventory_path" {
  value       = abspath(local_file.ansible_inventory.filename)
  description = "Absolute path to the generated Ansible inventory"
}
