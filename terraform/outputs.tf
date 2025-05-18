output "instance_id" {
  value = aws_instance.autogrow_host.id
}

output "public_ip" {
  value = aws_instance.autogrow_host.public_ip
}
