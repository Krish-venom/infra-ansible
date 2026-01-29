
output "web_instance_ids" {
  description = "EC2 instance IDs for all web servers"
  value       = aws_instance.web[*].id
}

output "web_private_ips" {
  description = "Private IP addresses of the web servers (used by Ansible inventory)"
  value       = aws_instance.web[*].private_ip
}

output "web_public_ips" {
  description = "Public IP addresses of the web servers (for access/debugging)"
  value       = aws_instance.web[*].public_ip
}

output "web_instance_names" {
  description = "EC2 Name tags of the web servers"
  value       = aws_instance.web[*].tags["Name"]
}

output "security_group_id" {
  description = "Security Group ID attached to the web servers"
  value       = aws_security_group.web_sg.id
}

output "subnet_id" {
  description = "Subnet ID where web servers are deployed"
  value       = aws_subnet.public_a.id
}

output "vpc_id" {
  description = "VPC ID for the web infrastructure"
  value       = aws_vpc.this.id
}
