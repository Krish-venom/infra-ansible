
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

# --- VPC (simple public subnet for quick start) ---
resource "aws_vpc" "this" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.80.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags = { Name = "${var.project_name}-public-a" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group: SSH from Jenkins, HTTP from anywhere ---
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow SSH from Jenkins and HTTP from anywhere"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from Jenkins"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_ingress_cidr]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# --- Ubuntu AMI lookup (22.04 LTS) ---
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
}

# --- EC2 instances ---
resource "aws_instance" "web" {
  count                       = var.instance_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-web-${count.index + 1}"
    Role = "webserver"
    Env  = "production"
  }
}

locals {
  private_ips = aws_instance.web[*].private_ip
  public_ips  = aws_instance.web[*].public_ip
}

# --- Generate Ansible inventory with PRIVATE IPs ---
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    private_ips = local.private_ips
    public_ips  = local.public_ips
  })
  filename = "${path.module}/../ansible-playbooks/inventory/hosts.ini"
}
