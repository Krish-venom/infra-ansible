variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-south-1"
}

variable "apache_instance_count" {
  description = "Number of Apache web server instances"
  type        = number
  default     = 2

  validation {
    condition     = var.apache_instance_count > 0 && var.apache_instance_count <= 10
    error_message = "Apache instance count must be between 1 and 10."
  }
}

variable "nginx_instance_count" {
  description = "Number of Nginx web server instances"
  type        = number
  default     = 2

  validation {
    condition     = var.nginx_instance_count > 0 && var.nginx_instance_count <= 10
    error_message = "Nginx instance count must be between 1 and 10."
  }
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Your AMI ID (must exist in selected region)."
  type        = string
  default     = "ami-019715e0d74f695be"

  validation {
    condition     = length(var.ami_id) > 0 && can(regex("^ami-[0-9a-fA-F]{8,}$", var.ami_id))
    error_message = "Provide a valid AMI ID (e.g., ami-xxxxxxxx) that exists in your chosen region."
  }
}

variable "jenkins_ip" {
  description = "Public IPv4 of Jenkins server (bare IP, no scheme/port), e.g., 13.201.85.232"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.jenkins_ip))
    error_message = "Jenkins IP must be a valid IPv4 address like 13.201.85.232 (no http:// or port)."
  }
}

variable "public_key_path" {
  description = "Path to SSH public key file for web server access"
  type        = string
  default     = "/var/lib/jenkins/.ssh/webserver-key.pub"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "devops-webapp"
}
