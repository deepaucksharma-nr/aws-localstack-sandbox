output "instance_id" {
  description = "ID of the monitoring instance"
  value       = aws_instance.monitoring.id
}

output "instance_public_ip" {
  description = "Public IP address of the monitoring instance"
  value       = aws_instance.monitoring.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the monitoring instance"
  value       = aws_instance.monitoring.private_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.monitoring.id
}