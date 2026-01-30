terraform {
  required_version = ">= 1.0"
  
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

###################
# VPC Configuration
###################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "devops-vpc"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "devops-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "devops-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "devops-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###################
# Security Groups
###################

resource "aws_security_group" "web" {
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  # HTTP Access
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS Access
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from Jenkins server only
  ingress {
    description = "SSH from Jenkins"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.jenkins_ip}/32"]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-server-sg"
  }
}

###################
# SSH Key Pair
###################

resource "aws_key_pair" "deployer" {
  key_name   = "webserver-key"
  public_key = file(var.public_key_path)

  tags = {
    Name = "webserver-deploy-key"
  }
}

###################
# EC2 Instances - Apache Servers
###################

resource "aws_instance" "apache" {
  count                  = var.apache_instance_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = aws_subnet.public.id

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              apt-get upgrade -y
              
              # Install Apache
              apt-get install -y apache2
              
              # Install Python for Ansible
              apt-get install -y python3 python3-pip
              
              # Enable and start Apache
              systemctl enable apache2
              systemctl start apache2
              
              # Create a placeholder page
              cat > /var/www/html/index.html <<HTML
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
              
              # Log completion
              echo "Apache setup completed at $(date)" >> /var/log/user-data.log
              EOF

  tags = {
    Name        = "apache-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "apache"
    Environment = "production"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

###################
# EC2 Instances - Nginx Servers
###################

resource "aws_instance" "nginx" {
  count                  = var.nginx_instance_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = aws_subnet.public.id

  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              apt-get upgrade -y
              
              # Install Nginx
              apt-get install -y nginx
              
              # Install Python for Ansible
              apt-get install -y python3 python3-pip
              
              # Enable and start Nginx
              systemctl enable nginx
              systemctl start nginx
              
              # Create a placeholder page
              cat > /var/www/html/index.html <<HTML
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
              
              # Remove default nginx page
              rm -f /var/www/html/index.nginx-debian.html
              
              # Log completion
              echo "Nginx setup completed at $(date)" >> /var/log/user-data.log
              EOF

  tags = {
    Name        = "nginx-server-${count.index + 1}"
    Role        = "webserver"
    ServerType  = "nginx"
    Environment = "production"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

###################
# Generate Ansible Inventory
###################

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    apache_servers = aws_instance.apache[*].public_ip
    nginx_servers  = aws_instance.nginx[*].public_ip
  })
  filename = "${path.module}/../ansible-playbooks/inventory/hosts.ini"

  depends_on = [aws_instance.apache, aws_instance.nginx]
}

###################
# Output Summary File
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
  
  SSH ACCESS:
  Apache Servers:
  ${join("\n  ", formatlist("ssh -i ~/.ssh/webserver-key ubuntu@%s", aws_instance.apache[*].public_ip))}
  
  Nginx Servers:
  ${join("\n  ", formatlist("ssh -i ~/.ssh/webserver-key ubuntu@%s", aws_instance.nginx[*].public_ip))}
  
  TOTAL SERVERS: ${var.apache_instance_count + var.nginx_instance_count}
  ========================================
  EOF
  
  filename = "${path.module}/deployment-summary.txt"
}
