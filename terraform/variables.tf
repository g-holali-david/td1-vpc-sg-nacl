variable "region" {
  type    = string
  default = "eu-west-3"
}

variable "owner" {
  type    = string
  default = "claire-david"
}

variable "key_name" {
  type    = string
  default = "cle-td-david"
}

variable "cidr" {
  type    = string
  default = "172.31.250.0/24"
}

variable "az" {
  type    = string
  default = "eu-west-3a"
}

variable "type_bastion" {
  type    = string
  default = "t2.micro"
}

variable "type_cible" {
  type    = string
  default = "t2.micro"
}
