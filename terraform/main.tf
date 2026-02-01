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
  }
}

provider "aws" {
  region = var.aws_region
}

################################
# Safer AZ selection
################################
data "aws_availability_zones" "available" {}

###################
# VPC + Networking
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

  # SSH from Jenkins public IP only (bare IPv4 expected)
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
# Generate SSH Keypair (TLS) and register in AWS
###################
# 1) Create a brand-new private key
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2) Register public key with AWS as an EC2 key pair
resource "aws_key_pair" "deployer" {
  key_name   = var.keypair_name    # e.g., "devops-generated-key"
  public_key = tls_private_key.web.public_key_openssh

  tags = {
    Name        = var.keypair_name
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# 3) Ensure output directory exists (to write keys/files)
resource "null_resource" "ensure_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../ansible-playbooks/inventory ${path.module}/../ansible-playbooks/keys"
  }
}

# 4) Save the generated keys to disk (so you can SSH / use Ansible)
resource "local_file" "private_key" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/../ansible-playbooks/keys/${var.keypair_name}.pem"
  file_permission = "0600"

  depends_on = [null_resource.ensure_dirs]
}

resource "local_file" "public_key" {
  content         = tls_private_key.web.public_key_openssh
  filename        = "${path.module}/../ansible-playbooks/keys/${var.keypair_name}.pub"
  file_permission = "0644"

  depends_on = [null_resource.ensure_dirs]
}

###################
# EC2 - Apache
###################
resource "aws_instance" "apache" {
  count                  = var.apache_instance_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = aws_subnet.public.id
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
                      body { font-family: Arial; text-align: center; padding: 50px; background: #f0f0f0; }
                      h1 { color: #d62828; }
                  </style>
              </head>
              <body>
                  <h1>🔴 Apache Server ${count.index + 1}</h1>
                  <p>Ready for deployment via Ansible</p>
                  <p>Powered by Apache HTTP Server</p>
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

  lifecycle {
    create_before_destroy = true
  }
}

###################
# EC2 - Nginx
###################
resource "aws_instance" "nginx" {
  count                  = var.nginx_instance_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = aws_subnet.public.id
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
                      body { font-family: Arial; text-align: center; padding: 50px; background: #f0f0f0; }
                      h1 { color: #009688; }
                  </style>
              </head>
              <body>
                  <h1>🔵 Nginx Server ${count.index + 1}</h1>
                  <p>Ready for deployment via Ansible</p>
                  <p>Powered by Nginx Web Server</p>
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

  lifecycle {
    create_before_destroy = true
  }
}

###################
# Ansible Inventory
###################
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    apache_servers = aws_instance.apache[*].public_ip
    nginx_servers  = aws_instance.nginx[*].public_ip
  })
  filename = "${path.module}/../ansible-playbooks/inventory/hosts.ini"

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

  NGINX URLs:
  ${join("\n  ", formatlist("- http://%s", aws_instance.nginx[*].public_ip))}

  SSH ACCESS (Ubuntu default user):
  Apache:
  ${join("\n  ", formatlist("ssh -i ../ansible-playbooks/keys/${var.keypair_name}.pem ubuntu@%s", aws_instance.apache[*].public_ip))}
  Nginx:
  ${join("\n  ", formatlist("ssh -i ../ansible-playbooks/keys/${var.keypair_name}.pem ubuntu@%s", aws_instance.nginx[*].public_ip))}

  TOTAL SERVERS: ${var.apache_instance_count + var.nginx_instance_count}
  ========================================
  EOF

  filename = "${path.module}/deployment-summary.txt"
}
