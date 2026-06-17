# Partie 3 - bastion (IP publique) + cible (sans IP publique)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.type_bastion
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.td.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]

  tags = {
    Name = "td-bastion-${var.owner}"
  }
}

resource "aws_instance" "cible" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.type_cible
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.td.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.cible.id]

  tags = {
    Name = "td-cible-${var.owner}"
  }
}
