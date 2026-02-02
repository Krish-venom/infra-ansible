# Region & environment
aws_region           = "ap-south-1"
environment          = "production"
project_name         = "devops-webapp"

# Your provided VPC ID
vpc_id               = "vpc-0bb695c41dc9db0a4"

# Leave empty to auto-pick the first subnet in that VPC
subnet_id            = ""

# Security group behavior
reuse_existing_sg    = true
existing_sg_name     = "web-server-sg"

# EC2 settings
keypair_name         = "deploy-key"
ansible_user         = "ubuntu"
instance_type        = "t3.micro"
apache_instance_count = 2
nginx_instance_count  = 2
