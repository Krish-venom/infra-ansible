# terraform.tfvars.example
# Copy this file to terraform.tfvars and update with your values

aws_region            = "ap-south-1"
apache_instance_count = 2
nginx_instance_count  = 2
instance_type         = "t3.micro"

# MUST BE ONLY THE PUBLIC IP OF JENKINS (NO http://, NO PORT, NO SLASH)
jenkins_ip = "3.110.120.129"

# Update this if your SSH key is in a different location
public_key_path = "/var/lib/jenkins/.ssh/webserver-key.pub"

environment  = "production"
project_name = "devops-webapp"
