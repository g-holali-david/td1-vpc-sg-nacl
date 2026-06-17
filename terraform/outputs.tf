output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_ssh" {
  value = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.bastion.public_ip}"
}

output "cible_private_ip" {
  value = aws_instance.cible.private_ip
}

output "subnet_id" {
  value = aws_subnet.td.id
}

output "nacl_id" {
  value = aws_network_acl.td.id
}
