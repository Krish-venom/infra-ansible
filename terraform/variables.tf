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

# Base key pair name; a random suffix is appended to avoid duplicates
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
  default     = "ami-019715e0d74f695be"  # Ensure this exists in your chosen region

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
