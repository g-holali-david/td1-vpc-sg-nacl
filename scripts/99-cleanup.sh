#!/bin/bash
# Partie 7 - Nettoyage OBLIGATOIRE, par TAG (marche quel que soit le run qui a cree les ressources).
# Idempotent : ne fait rien sur ce qui n'existe pas. On ne touche ni au VPC, ni a l'IGW.
# NB : volontairement SANS "set -e" — on veut tenter chaque suppression meme si une ressource manque.
set -uo pipefail

REGION=eu-west-3
OWNER=david   # doit correspondre au OWNER de run-all.sh

echo "### Recherche des ressources taguees -$OWNER ###"

INSTANCES=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=td-bastion-$OWNER,td-cible-$OWNER" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
SUBNET=$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=tag:Name,Values="td-subnet-$OWNER" --query "Subnets[0].SubnetId" --output text)
RT=$(aws ec2 describe-route-tables --region "$REGION" \
  --filters Name=tag:Name,Values="td-rt-$OWNER" --query "RouteTables[0].RouteTableId" --output text)
NACL=$(aws ec2 describe-network-acls --region "$REGION" \
  --filters Name=tag:Name,Values="td-nacl-$OWNER" --query "NetworkAcls[0].NetworkAclId" --output text)
SG_BASTION=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="td-sg-bastion-$OWNER" --query "SecurityGroups[0].GroupId" --output text)
SG_CIBLE=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="td-sg-cible-$OWNER" --query "SecurityGroups[0].GroupId" --output text)

# 1. Terminer les instances et ATTENDRE (sinon DependencyViolation sur SG/subnet)
if [ -n "$INSTANCES" ]; then
  echo "Terminate instances : $INSTANCES"
  aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCES >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCES
fi

# 2. Supprimer les SG (cible AVANT bastion : sg-cible reference sg-bastion)
if [ "$SG_CIBLE" != "None" ];   then aws ec2 delete-security-group --region "$REGION" --group-id "$SG_CIBLE"   && echo "SG cible supprime";   fi
if [ "$SG_BASTION" != "None" ]; then aws ec2 delete-security-group --region "$REGION" --group-id "$SG_BASTION" && echo "SG bastion supprime"; fi

# 3. Supprimer le sous-reseau (retire ses associations NACL + route-table), puis la NACL, puis la RT
if [ "$SUBNET" != "None" ]; then aws ec2 delete-subnet      --region "$REGION" --subnet-id "$SUBNET"      && echo "Subnet supprime";       fi
if [ "$NACL"   != "None" ]; then aws ec2 delete-network-acl --region "$REGION" --network-acl-id "$NACL"   && echo "NACL supprimee";        fi
if [ "$RT"     != "None" ]; then aws ec2 delete-route-table --region "$REGION" --route-table-id "$RT"     && echo "Route-table supprimee"; fi

echo "Nettoyage termine. Verifie dans la console qu'il ne reste rien a toi."
