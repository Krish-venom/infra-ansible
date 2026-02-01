# variables.tf

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment tag (e.g., dev, staging, production)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project tag for all resources"
  type        = string
  default     = "devops-webapp"
}

# ⬇️ NEW: used for the generated AWS key pair name and the local key filenames
variable "keypair_name" {
  description = "Name for the generated AWS key pair and local key files"
  type        = string
  default     = "devops-generated-key"
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
  # Optional validation:
  # validation {
  #   condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
  #   error_message = "Instance type must look like 't3.micro', 't3.small', etc."
  # }
}

# IMPORTANT: Ensure this AMI exists in your selected region and matches your user_data (Ubuntu recommended)
variable "ami_id" {
  description = "AMI ID to use for EC2 instances (Ubuntu if using apt-get in user_data)"
  type        = string
  default     = "ami-019715e0d74f695be"

  validation {
    condition     = length(var.ami_id) > 0 && can(regex("^ami-[0-9a-fA-F]{8,}$", var.ami_id))
    error_message = "Provide a valid AMI ID (e.g., ami-xxxxxxxx) available in your region."
  }
}

# Must be a bare IPv4; used to restrict SSH in the Security Group as <ip>/32
variable "jenkins_ip" {
  description = "Public IPv4 of the Jenkins server (no scheme/port), e.g., 3.110.120.129"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.jenkins_ip))
    error_message = "jenkins_ip must be a valid IPv4 like 3.110.120.129 (no http:// or port)."
  }
}
