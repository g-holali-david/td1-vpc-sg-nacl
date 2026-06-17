# Partie 4 - Security Groups (stateful)
resource "aws_security_group" "bastion" {
  name        = "td-sg-bastion-${var.owner}"
  description = "SSH bastion"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "td-sg-bastion-${var.owner}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = local.my_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "cible" {
  name        = "td-sg-cible-${var.owner}"
  description = "Acces depuis bastion"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "td-sg-cible-${var.owner}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cible_ssh" {
  security_group_id            = aws_security_group.cible.id
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_ingress_rule" "cible_icmp" {
  security_group_id            = aws_security_group.cible.id
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "icmp"
  from_port                    = -1
  to_port                      = -1
}

resource "aws_vpc_security_group_egress_rule" "cible_all" {
  security_group_id = aws_security_group.cible.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Partie 5 - NACL (stateless) sur NOTRE sous-reseau
resource "aws_network_acl" "td" {
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = [aws_subnet.td.id]

  tags = {
    Name = "td-nacl-${var.owner}"
  }
}

resource "aws_network_acl_rule" "ssh_in" {
  network_acl_id = aws_network_acl.td.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.my_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "ephemeral_out" {
  network_acl_id = aws_network_acl.td.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}
