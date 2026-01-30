# outputs.tf

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the web server security group"
  value       = aws_security_group.web.id
}

###################
# Apache Outputs
###################

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

###################
# Nginx Outputs
###################

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

###################
# Combined Outputs
###################

output "all_server_ips" {
  description = "All server IP addresses"
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

output "ssh_commands" {
  description = "SSH commands to connect to all servers"
  value = concat(
    formatlist("ssh -i ~/.ssh/webserver-key ubuntu@%s  # Apache-%s", aws_instance.apache[*].public_ip, range(1, var.apache_instance_count + 1)),
    formatlist("ssh -i ~/.ssh/webserver-key ubuntu@%s  # Nginx-%s", aws_instance.nginx[*].public_ip, range(1, var.nginx_instance_count + 1))
  )
}

output "deployment_time" {
  description = "Timestamp of deployment"
  value       = timestamp()
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}

output "server_summary" {
  description = "Summary of all servers"
  value = {
    total_apache_servers = var.apache_instance_count
    total_nginx_servers  = var.nginx_instance_count
    total_servers        = var.apache_instance_count + var.nginx_instance_count
  }
}
