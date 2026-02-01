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

################################
# ---------- Variables ----------
################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project tag"
  type        = string
  default     = "devops-webapp"
}

# 👉 Existing VPC ID to use (your default VPC)
variable "vpc_id" {
  description = "Existing VPC ID to deploy into"
  type        = string
  default     = "vpc-0bb695c41dc9db0a4"
}

# Optional: specific subnet ID in that VPC; leave empty to auto-pick the first subnet in the VPC
variable "subnet_id" {
  description = "Existing subnet ID in the VPC; if empty, the first subnet in that VPC is used"
  type        = string
  default     = ""
}

# Base key pair name; a random suffix is added to avoid duplicates
variable "keypair_name" {
  description = "Base name for the generated AWS key pair and local key files"
  type        = string
  default     = "devops-generated-key"
}

variable "ansible_user" {
  description = "Remote SSH user for Ansible (ubuntu for Ubuntu; ec2-user for Amazon Linux)"
  type        = string
  default     = "ubuntu"
}

variable "apache_instance_count" {
  description = "Number of Apache servers"
  type        = number
  default     = 2

  validation {
    condition     = var.apache_instance_count > 0 && var.apache_instance_count <= 10
    error_message = "Apache count must be between 1 and 10."
  }
}

variable "nginx_instance_count" {
  description = "Number of Nginx servers"
  type        = number
  default     = 2

  validation {
    condition     = var.nginx_instance_count > 0 && var.nginx_instance_count <= 10
    error_message = "Nginx count must be between 1 and 10."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID (Ubuntu recommended if using apt-get in user_data)"
  type        = string
  default     = "ami-019715e0d74f695be"  # Ensure this exists in your region

  validation {
    condition     = length(var.ami_id) > 0 && can(regex("^ami-[0-9a-fA-F]{8,}$", var.ami_id))
    error_message = "Provide a valid AMI ID (ami-xxxxxxxx) available in your region."
  }
}

variable "jenkins_ip" {
  description = "Public IPv4 of Jenkins (bare IP, no scheme/port), e.g., 3.110.120.129"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.jenkins_ip))
    error_message = "jenkins_ip must be a bare IPv4 like 3.110.120.129 (no http:// or port)."
  }
}

################################
# ---------- Provider ----------
################################

provider "aws" {
  region = var.aws_region
}

################################
# ---------- Data Sources ----------
################################

# Reuse existing VPC by ID
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Get all subnets in that VPC; we'll pick the first unless you pass var.subnet_id
data "aws_subnets" "in_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

################################
# ---------- Locals ----------
################################

locals {
  # Prefer a specific subnet if provided, else pick the first found in the VPC
  selected_subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.in_vpc.ids[0]
}

################################
# ---------- Security Group ----------
################################

resource "aws_security_group" "web" {
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH only from Jenkins IP (/32)
  ingress {
    description = "SSH from Jenkins"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.jenkins_ip}/32"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-server-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

################################
# ---------- Key Pair Generation ----------
################################

# Random suffix to avoid AWS duplicate key errors
resource "random_id" "kp" {
  byte_length = 2  # 4 hex chars, e.g., f039
}

locals {
  effective_key_name = "${var.keypair_name}-${random_id.kp.hex}"
}

# Generate new private/public key
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Register public key in AWS
resource "aws_key_pair" "deployer" {
  key_name   = local.effective_key_name
  public_key = tls_private_key.web.public_key_openssh

  tags = {
    Name        = local.effective_key_name
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Ensure local dirs for inventory & keys exist
resource "null_resource" "ensure_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../ansible-playbooks/inventory ${path.module}/../ansible-playbooks/keys"
  }
}

# Save generated keys locally (gitignore these)
resource "local_file" "private_key" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/../ansible-playbooks/keys/${aws_key_pair.deployer.key_name}.pem"
  file_permission = "0600"
  depends_on      = [null_resource.ensure_dirs]
}

resource "local_file" "public_key" {
  content         = tls_private_key.web.public_key_openssh
  filename        = "${path.module}/../ansible-playbooks/keys/${aws_key_pair.deployer.key_name}.pub"
  file_permission = "0644"
  depends_on      = [null_resource.ensure_dirs]
}

################################
# ---------- EC2 - Apache ----------
################################

resource "aws_instance" "apache" {
  count                       = var.apache_instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = local.selected_subnet_id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get upgrade -y
                apt-get install -y apache2 python3 python3-pip
                systemctl enable apache2
                systemctl start apache2
                WEBROOT="/var/www/html"
              elif command -v yum >/dev/null 2>&1; then
                yum update -y
                yum install -y httpd python3
                systemctl enable httpd
                systemctl start httpd
                WEBROOT="/var/www/html"
                [ -d "$WEBROOT" ] || WEBROOT="/usr/share/httpd/noindex"
              fi

              cat > "$WEBROOT/index.html" <<HTML
              <!DOCTYPE html>
              <html>
              <head>
                <title>Apache Server ${count.index + 1}</title>
                <style>
                  body { font-family: Arial; text-align:center; padding:50px; background:#f0f0f0; }
                  h1 { color:#d62828; }
                </style>
              </head>
              <body>
                <h1>🔴 Apache Server ${count.index + 1}</h1>
                <p>Ready for deployment via Ansible</p>
              </body>
              </html>
HTML
              echo "Apache setup completed at $(date)" >> /var/log/user-data.log
              EOF

  tags = {
    Name        = "apache-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "apache"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  lifecycle { create_before_destroy = true }
}

################################
# ---------- EC2 - Nginx ----------
################################

resource "aws_instance" "nginx" {
  count                       = var.nginx_instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = local.selected_subnet_id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              if command -v apt-get >/dev/null 2>&1; then
                apt-get update
                apt-get upgrade -y
                apt-get install -y nginx python3 python3-pip
                systemctl enable nginx
                systemctl start nginx
                WEBROOT="/var/www/html"
                rm -f /var/www/html/index.nginx-debian.html || true
              elif command -v yum >/dev/null 2>&1; then
                yum update -y
                amazon-linux-extras install -y nginx1 || yum install -y nginx
                systemctl enable nginx
                systemctl start nginx
                WEBROOT="/usr/share/nginx/html"
              fi

              cat > "$WEBROOT/index.html" <<HTML
              <!DOCTYPE html>
              <html>
              <head>
                <title>Nginx Server ${count.index + 1}</title>
                <style>
                  body { font-family: Arial; text-align:center; padding:50px; background:#f0f0f0; }
                  h1 { color:#009688; }
                </style>
              </head>
              <body>
                <h1>🔵 Nginx Server ${count.index + 1}</h1>
                <p>Ready for deployment via Ansible</p>
              </body>
              </html>
HTML
              echo "Nginx setup completed at $(date)" >> /var/log/user-data.log
              EOF

  tags = {
    Name        = "nginx-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "nginx"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  lifecycle { create_before_destroy = true }
}

################################
# ---------- Dynamic Ansible Inventory ----------
################################

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
    "ansible_ssh_private_key_file=../keys/${aws_key_pair.deployer.key_name}.pem",
    "ansible_python_interpreter=/usr/bin/python3",
    "",
    "[nginx:vars]",
    "ansible_user=${var.ansible_user}",
    "ansible_ssh_private_key_file=../keys/${aws_key_pair.deployer.key_name}.pem",
    "ansible_python_interpreter=/usr/bin/python3",
    ""
  ])

  filename   = "${path.module}/../ansible-playbooks/inventory/hosts.ini"
  depends_on = [null_resource.ensure_dirs, aws_instance.apache, aws_instance.nginx]
}

################################
# ---------- Deployment Summary (optional nice-to-have) ----------
################################

resource "local_file" "deployment_summary" {
  content = <<-EOF
  ========================================
  DEPLOYMENT SUMMARY
  ========================================
  Deployment Time: ${timestamp()}
  Region: ${var.aws_region}
  Selected VPC ID: ${data.aws_vpc.selected.id}
  Selected Subnet ID: ${local.selected_subnet_id}

  APACHE SERVERS (${var.apache_instance_count}):
  ${join("\n  ", formatlist("- %s (Instance: %s) - Apache", aws_instance.apache[*].public_ip, aws_instance.apache[*].id))}

  NGINX SERVERS (${var.nginx_instance_count}):
  ${join("\n  ", formatlist("- %s (Instance: %s) - Nginx", aws_instance.nginx[*].public_ip, aws_instance.nginx[*].id))}

  APACHE URLs:
  ${join("\n  ", formatlist("- http://%s", aws_instance.apache[*].public_ip))}

  NGINX  URLs:
  ${join("\n  ", formatlist("- http://%s", aws_instance.nginx[*].public_ip))}

  SSH (default user: ${var.ansible_user}):
  Apache:
  ${join("\n  ", formatlist("ssh -i ../ansible-playbooks/keys/${aws_key_pair.deployer.key_name}.pem ${var.ansible_user}@%s", aws_instance.apache[*].public_ip))}
  Nginx:
  ${join("\n  ", formatlist("ssh -i ../ansible-playbooks/keys/${aws_key_pair.deployer.key_name}.pem ${var.ansible_user}@%s", aws_instance.nginx[*].public_ip))}

  ========================================
  EOF

  filename = "${path.module}/deployment-summary.txt"
}

################################
# ---------- Outputs (absolute paths for Jenkins) ----------
################################

output "effective_keypair_name" {
  description = "The actual AWS key pair name used (with random suffix)"
  value       = aws_key_pair.deployer.key_name
}

output "generated_private_key_path" {
  description = "Absolute path to the generated private key"
  value       = abspath(local_file.private_key.filename)
  sensitive   = true
}

output "inventory_path" {
  description = "Absolute path to the generated Ansible inventory"
  value       = abspath(local_file.ansible_inventory.filename)
}
