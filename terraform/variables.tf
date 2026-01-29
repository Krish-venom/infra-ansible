
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_count" {
  description = "Number of web instances"
  type        = number
  default     = 4
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name (NOT the .pem filename)"
  type        = string
}

variable "jenkins_ingress_cidr" {
  description = "CIDR allowed to SSH (your Jenkins public IP /32)"
  type        = string
}

variable "project_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "demo"
}
