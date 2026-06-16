#!/bin/bash
# Partie 4 - Security Groups (pare-feu d'instance, stateful)

REGION=eu-west-3
VPC=vpc-0ebcdb39f7a526ef9     # VPC par defaut
MON_IP=82.96.161.255/32       # mon IP (curl https://checkip.amazonaws.com)
BASTION=i-02d790e1cb08249b4   # instance bastion (Partie 3)
CIBLE=i-067a09cb0e69d3902     # instance cible (Partie 3)

# sg-bastion : SSH (22) depuis MON IP seulement
SG_BASTION=$(aws ec2 create-security-group --region $REGION \
  --group-name td-sg-bastion-david --description "SSH bastion" --vpc-id $VPC \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $SG_BASTION --protocol tcp --port 22 --cidr $MON_IP

# sg-cible : SSH + ICMP dont la SOURCE est sg-bastion (pas une plage d'IP)
SG_CIBLE=$(aws ec2 create-security-group --region $REGION \
  --group-name td-sg-cible-david --description "Acces depuis bastion" --vpc-id $VPC \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $SG_CIBLE --protocol tcp --port 22 --source-group $SG_BASTION

aws ec2 authorize-security-group-ingress --region $REGION \
  --group-id $SG_CIBLE --protocol icmp --port -1 --source-group $SG_BASTION

# Attacher les SG aux instances
aws ec2 modify-instance-attribute --region $REGION --instance-id $BASTION --groups $SG_BASTION
aws ec2 modify-instance-attribute --region $REGION --instance-id $CIBLE  --groups $SG_CIBLE

echo "sg-bastion = $SG_BASTION"
echo "sg-cible   = $SG_CIBLE"

# Test : ssh -i cle-td.pem ec2-user@IP_BASTION, puis depuis le bastion :
#        ping 172.31.x.x  et  ssh ec2-user@172.31.x.x
