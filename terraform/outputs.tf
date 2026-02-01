# outputs.tf

# Core infra references
output "vpc_id" {
  description = "Selected VPC ID (existing)"
  value       = data.aws_vpc.selected.id
}

output "subnet_id" {
  description = "Selected subnet ID (either provided or first in the VPC)"
  value       = local.selected_subnet_id
}

output "security_group_id" {
  description = "ID of the web server security group"
  value       = aws_security_group.web.id
}

# Key pair info
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

# Apache group
output "apache_instance_ids" {
  description = "List of Apache EC2 instance IDs"
  value       = aws_instance.apache[*].id
}

output "apache_public_ips" {
  description = "List of Apache server public IP addresses"
  value       = aws_instance.apache[*].public_ip
}

output "apache_private_ips" {
  description = "List of Apache server private IP addresses"
  value       = aws_instance.apache[*].private_ip
}

output "apache_urls" {
  description = "URLs to access Apache servers"
  value       = formatlist("http://%s", aws_instance.apache[*].public_ip)
}

# Nginx group
output "nginx_instance_ids" {
  description = "List of Nginx EC2 instance IDs"
  value       = aws_instance.nginx[*].id
}

output "nginx_public_ips" {
  description = "List of Nginx server public IP addresses"
  value       = aws_instance.nginx[*].public_ip
}

output "nginx_private_ips" {
  description = "List of Nginx server private IP addresses"
  value       = aws_instance.nginx[*].private_ip
}

output "nginx_urls" {
  description = "URLs to access Nginx servers"
  value       = formatlist("http://%s", aws_instance.nginx[*].public_ip)
}

# Combined convenience outputs
output "all_server_ips" {
  description = "All server IP addresses grouped by tier"
  value = {
    apache = aws_instance.apache[*].public_ip
    nginx  = aws_instance.nginx[*].public_ip
  }
}

output "all_server_urls" {
  description = "All server URLs"
  value = concat(
    formatlist("http://%s (Apache)", aws_instance.apache[*].public_ip),
    formatlist("http://%s (Nginx)", aws_instance.nginx[*].public_ip)
  )
}
