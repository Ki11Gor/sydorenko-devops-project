output "instance_id" {
  value = aws_instance.app.id
}

output "instance_ip" {
  value = aws_instance.app.public_ip
}

output "security_group_id" {
  value = aws_security_group.app.id
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}:3000/"
}
