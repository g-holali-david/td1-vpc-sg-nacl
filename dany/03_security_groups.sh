#!/usr/bin/env bash
# =============================================================================
# 03_security_groups.sh  —  TD Partie 4 : Security Groups (stateful)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -n "${VPC_ID:-}" ]  || die "VPC_ID manquant : lancez d'abord 02_explore_vpc.sh"
[ -n "${MY_CIDR:-}" ] || die "MY_CIDR manquant : lancez d'abord 01_prerequis.sh"

# Petit utilitaire : récupère l'ID d'un SG par son nom (vide si absent)
sg_id_by_name() {
  aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$1" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null | grep -v '^None$' || true
}

# 1) sg-bastion 
SG_BASTION="$(sg_id_by_name "$SG_BASTION_NAME")"
if [ -z "$SG_BASTION" ]; then
  log "Création de $SG_BASTION_NAME…"
  SG_BASTION="$(aws ec2 create-security-group --region "$REGION" \
    --group-name "$SG_BASTION_NAME" --description "TD bastion - SSH depuis mon IP" \
    --vpc-id "$VPC_ID" --query "GroupId" --output text)"
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_BASTION" --protocol tcp --port 22 --cidr "$MY_CIDR" >/dev/null
fi
state_set SG_BASTION "$SG_BASTION"
ok "sg-bastion = $SG_BASTION  (ingress TCP 22 <- $MY_CIDR)"

#2) sg-cible (source = sg-bastion) 
SG_CIBLE="$(sg_id_by_name "$SG_CIBLE_NAME")"
if [ -z "$SG_CIBLE" ]; then
  log "Création de $SG_CIBLE_NAME…"
  SG_CIBLE="$(aws ec2 create-security-group --region "$REGION" \
    --group-name "$SG_CIBLE_NAME" --description "TD cible - acces depuis le bastion" \
    --vpc-id "$VPC_ID" --query "GroupId" --output text)"
  # Source = un AUTRE Security Group (et non une plage d'IP)
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_CIBLE" --protocol tcp --port 22 --source-group "$SG_BASTION" >/dev/null
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_CIBLE" --protocol icmp --port -1 --source-group "$SG_BASTION" >/dev/null
fi
state_set SG_CIBLE "$SG_CIBLE"
ok "sg-cible   = $SG_CIBLE  (ingress TCP 22 + ICMP <- sg-bastion)"

log "Règles entrantes des deux SG :"
aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_BASTION" "$SG_CIBLE" \
  --query "SecurityGroups[].{Nom:GroupName,Id:GroupId,Entrantes:IpPermissions}" --output json

ok "Partie 4 (création des SG) terminée."
