#!/usr/bin/env bash
# =============================================================================
# 02_explore_vpc.sh  —  TD Partie 2 : Explorer le VPC par défaut
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools

#  1) VPC par défaut 
log "Recherche du VPC par défaut…"
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text)"
[ "$VPC_ID" != "None" ] || die "Aucun VPC par défaut trouvé dans $REGION."
state_set VPC_ID "$VPC_ID"
aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" \
  --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock,Default:IsDefault}" --output table

# 2) Internet Gateway 
IGW_ID="$(aws ec2 describe-internet-gateways --region "$REGION" \
  --filters Name=attachment.vpc-id,Values="$VPC_ID" \
  --query "InternetGateways[0].InternetGatewayId" --output text)"
state_set IGW_ID "$IGW_ID"
log "Internet Gateway du VPC : $IGW_ID"

# 3) Sous-réseaux 
log "Sous-réseaux du VPC par défaut :"
aws ec2 describe-subnets --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "Subnets[].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,AutoPublicIp:MapPublicIpOnLaunch}" \
  --output table

# 4) Sélection d'un sous-réseau PUBLIC le moins peuplé 

if [ -n "${SUBNET_ID:-}" ]; then
  log "SUBNET_ID forcé par l'environnement : $SUBNET_ID"
else
  log "Sélection automatique d'un sous-réseau public peu peuplé…"
  PUBLIC_SUBNETS="$(aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=map-public-ip-on-launch,Values=true \
    --query "Subnets[].SubnetId" --output text)"
  [ -n "$PUBLIC_SUBNETS" ] || die "Aucun sous-réseau public trouvé."
  BEST=""; BEST_N=999999
  for s in $PUBLIC_SUBNETS; do
    n="$(aws ec2 describe-network-interfaces --region "$REGION" \
          --filters Name=subnet-id,Values="$s" \
          --query "length(NetworkInterfaces)" --output text)"
    echo "    $s : $n ENI"
    if [ "$n" -lt "$BEST_N" ]; then BEST_N="$n"; BEST="$s"; fi
  done
  SUBNET_ID="$BEST"
fi

# AZ du sous-réseau retenu (les 2 instances iront dans le MÊME sous-réseau)
SUBNET_AZ="$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$SUBNET_ID" \
  --query "Subnets[0].AvailabilityZone" --output text)"
state_set SUBNET_ID "$SUBNET_ID"
state_set SUBNET_AZ "$SUBNET_AZ"
ok "Sous-réseau retenu : $SUBNET_ID (AZ $SUBNET_AZ)"

# 5) Vérification de la route 0.0.0.0/0 
log "Routes 0.0.0.0/0 du VPC (doivent pointer vers l'IGW = sous-réseaux publics) :"
aws ec2 describe-route-tables --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0'].{Dest:DestinationCidrBlock,Gateway:GatewayId}" \
  --output table

ok "Partie 2 terminée."
