#!/bin/bash
# Partie 5 - NACL (pare-feu de sous-reseau, stateless)
# Le piege classique : autoriser l'entree mais oublier le trafic retour.

REGION=eu-west-3
VPC=vpc-0ebcdb39f7a526ef9         # VPC par defaut
SUBNET=subnet-0278f23e07970b7be   # NOTRE sous-reseau dedie 172.31.250.0/24 (cree pour le TD, pas partage)
MON_IP=82.96.161.255/32

# Voir l'association NACL actuelle du sous-reseau -> NOTE l'AssociationId pour la Partie 7
aws ec2 describe-network-acls --region $REGION \
  --filters Name=association.subnet-id,Values=$SUBNET \
  --query "NetworkAcls[].Associations[]" --output table

# Creer la NACL
NACL=$(aws ec2 create-network-acl --region $REGION --vpc-id $VPC \
  --query NetworkAcl.NetworkAclId --output text)
echo "NACL = $NACL"

# Associer NOTRE NACL a NOTRE sous-reseau (sans danger : sous-reseau dedie, pas partage)
ASSOC=$(aws ec2 describe-network-acls --region $REGION \
  --filters Name=association.subnet-id,Values=$SUBNET \
  --query "NetworkAcls[].Associations[?SubnetId=='$SUBNET'].NetworkAclAssociationId" --output text)
aws ec2 replace-network-acl-association --region $REGION \
  --association-id $ASSOC --network-acl-id $NACL

# Entree : autoriser SSH depuis mon IP
aws ec2 create-network-acl-entry --region $REGION --network-acl-id $NACL \
  --rule-number 100 --protocol 6 --port-range From=22,To=22 \
  --cidr-block $MON_IP --rule-action allow --ingress

# >>> TESTE ICI : la connexion reste BLOQUEE (pas de regle de sortie) <<<

# Sortie : ports ephemeres pour le trafic retour (indispensable en stateless)
aws ec2 create-network-acl-entry --region $REGION --network-acl-id $NACL \
  --rule-number 100 --protocol 6 --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress

# >>> RETESTE : maintenant la connexion PASSE <<<
