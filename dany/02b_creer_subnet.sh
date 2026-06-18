#!/usr/bin/env bash
# =============================================================================
# 02b_creer_subnet.sh  —  (Optionnel) Créer SON propre sous-réseau public
# -----------------------------------------------------------------------------
# Le PDF du TD réutilise un sous-réseau existant. Mais dans la classe, chaque
# étudiant crée le sien (td-subnet-<nom> + td-rt-<nom> + sa NACL) pour qu'il
# soit visible et isolé. Ce script reproduit ce pattern :
#   - crée td-subnet-<prefix> avec un /24 libre
#   - active l'attribution automatique d'IP publique
#   - crée une table de routage td-rt-<prefix> avec 0.0.0.0/0 -> Internet Gateway
#   - enregistre ce sous-réseau comme SUBNET_ID pour la suite du TD
#
# À lancer APRÈS 02_explore_vpc.sh (qui fournit VPC_ID et IGW_ID).
# Le nettoyage (08) supprimera ce sous-réseau et sa table de routage.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -n "${VPC_ID:-}" ] || die "VPC_ID manquant : lancez d'abord 02_explore_vpc.sh"

SUBNET_NAME="td-subnet-${NAME_PREFIX}"
RT_NAME="td-rt-${NAME_PREFIX}"
SUBNET_AZ="${SUBNET_AZ_FORCE:-eu-west-3a}"

# IGW du VPC (si 02 ne l'a pas déjà enregistré)
if [ -z "${IGW_ID:-}" ] || [ "$IGW_ID" = "None" ]; then
  IGW_ID="$(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters Name=attachment.vpc-id,Values="$VPC_ID" \
    --query "InternetGateways[0].InternetGatewayId" --output text)"
fi
[ "$IGW_ID" != "None" ] || die "Internet Gateway introuvable pour $VPC_ID."

# Idempotence : si le sous-réseau existe déjà (par son tag Name), on le réutilise
EXIST="$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=tag:Name,Values="$SUBNET_NAME" \
  --query "Subnets[0].SubnetId" --output text 2>/dev/null | grep -v '^None$' || true)"
if [ -n "$EXIST" ]; then
  warn "Le sous-réseau $SUBNET_NAME existe déjà ($EXIST) : réutilisation."
  state_set SUBNET_ID "$EXIST"
  exit 0
fi

# --- 1) Choix d'un CIDR /24 libre dans 172.31.x.0/24 ------------------------
log "Recherche d'un bloc /24 libre…"
USED="$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "Subnets[].CidrBlock" --output text | tr '\t' '\n')"
CIDR=""
for o in 40 42 44 46 48 80 110 170 180 190 230 ; do
  cand="172.31.${o}.0/24"
  echo "$USED" | grep -qx "$cand" || { CIDR="$cand"; break; }
done
[ -n "$CIDR" ] || die "Aucun /24 libre trouvé dans la liste candidate."
ok "CIDR retenu : $CIDR"

# --- 2) Création du sous-réseau + IP publique auto --------------------------
log "Création du sous-réseau $SUBNET_NAME ($CIDR, $SUBNET_AZ)…"
SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" \
  --cidr-block "$CIDR" --availability-zone "$SUBNET_AZ" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]" \
  --query "Subnet.SubnetId" --output text)"
aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$SUBNET_ID" --map-public-ip-on-launch
ok "Sous-réseau créé : $SUBNET_ID"

# --- 3) Table de routage dédiée -> Internet Gateway -------------------------
log "Création de la table de routage $RT_NAME (0.0.0.0/0 -> $IGW_ID)…"
RT_DANY="$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$RT_NAME}]" \
  --query "RouteTable.RouteTableId" --output text)"
aws ec2 create-route --region "$REGION" --route-table-id "$RT_DANY" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --region "$REGION" \
  --route-table-id "$RT_DANY" --subnet-id "$SUBNET_ID" >/dev/null
ok "Table de routage $RT_DANY associée (sous-réseau désormais public)."

# --- 4) Enregistrement pour la suite ----------------------------------------
state_set SUBNET_ID "$SUBNET_ID"
state_set SUBNET_AZ "$SUBNET_AZ"
state_set RT_DANY "$RT_DANY"
state_set CREATED_SUBNET "yes"
ok "Sous-réseau $SUBNET_NAME prêt et sélectionné pour le TD."
