#!/bin/bash
# Partie 3 - Lancer le bastion (IP publique) et la cible (sans IP publique)

REGION=eu-west-3
AMI=ami-05dfcc4b49790367c   # Amazon Linux 2023 (eu-west-3, via describe-images)
SUBNET=subnet-0278f23e07970b7be   # NOTRE sous-reseau 172.31.250.0/24 (cree pour le TD)
KEY=cle-td           # nom de ta paire de cles

# Bastion : AVEC IP publique (porte d'entree SSH)
BASTION=$(aws ec2 run-instances --region $REGION --image-id $AMI \
  --instance-type t3.micro --key-name $KEY \
  --subnet-id $SUBNET --associate-public-ip-address --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=td-bastion-david}]' \
  --query "Instances[0].InstanceId" --output text)
echo "BASTION = $BASTION"

# Cible : SANS IP publique (serveur protege)
# t2.micro (1 vCPU) car le compte partage atteint sa limite de 32 vCPU
CIBLE=$(aws ec2 run-instances --region $REGION --image-id $AMI \
  --instance-type t2.micro --key-name $KEY \
  --subnet-id $SUBNET --no-associate-public-ip-address --count 1 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=td-cible-david}]' \
  --query "Instances[0].InstanceId" --output text)
echo "CIBLE   = $CIBLE"

# Note ensuite : IP publique du bastion + IP privee de la cible (172.31.x.x)
