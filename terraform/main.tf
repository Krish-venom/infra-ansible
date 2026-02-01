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

provider "aws" {
  region = var.aws_region
}

################################
# Availability Zones
################################
data "aws_availability_zones" "available" {}

###################
# VPC & Networking
###################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "devops-vpc"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "devops-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "devops-public-subnet"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "devops-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###################
# Security Group
###################
resource "aws_security_group" "web" {
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

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

  # SSH only from Jenkins public IP (bare IPv4)
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

###################
# Generate SSH keypair with random suffix to avoid duplicates
###################
resource "random_id" "kp" {
  byte_length = 2  # 4 hex chars
}

locals {
  effective_key_name = "${var.keypair_name}-${random_id.kp.hex}"
}

# Create brand-new key pair
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

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

# Save generated keys locally (gitignore them)
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

###################
# EC2 - Apache
###################
resource "aws_instance" "apache" {
  count                         = var.apache_instance_count
  ami                           = var.ami_id
  instance_type                 = var.instance_type
  key_name                      = aws_key_pair.deployer.key_name
  vpc_security_group_ids        = [aws_security_group.web.id]
  subnet_id                     = aws_subnet.public.id
  associate_public_ip_address   = true

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

###################
# EC2 - Nginx
###################
resource "aws_instance" "nginx" {
  count                         = var.nginx_instance_count
  ami                           = var.ami_id
  instance_type                 = var.instance_type
  key_name                      = aws_key_pair.deployer.key_name
  vpc_security_group_ids        = [aws_security_group.web.id]
  subnet_id                     = aws_subnet.public.id
  associate_public_ip_address   = true

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

###################
# Ansible Inventory (dynamic; no hardcoding)
###################
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

###################
# Deployment Summary
###################
resource "local_file" "deployment_summary" {
  content = <<-EOF
  ========================================
  DEPLOYMENT SUMMARY
  ========================================
  Deployment Time: ${timestamp()}
  Region: ${var.aws_region}
  VPC ID: ${aws_vpc.main.id}
  Subnet ID: ${aws_subnet.public.id}

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

  TOTAL SERVERS: ${var.apache_instance_count + var.nginx_instance_count}
  ========================================
  EOF

  filename = "${path.module}/deployment-summary.txt"
}

###################
# Outputs (absolute paths for Jenkins)
###################
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
