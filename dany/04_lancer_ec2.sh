#!/usr/bin/env bash
# =============================================================================
# 04_lancer_ec2.sh  —  TD Partie 3 : Lancer deux instances EC2
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -n "${SUBNET_ID:-}" ]  || die "SUBNET_ID manquant : lancez 02_explore_vpc.sh"
[ -n "${SG_BASTION:-}" ] || die "SG_BASTION manquant : lancez 03_security_groups.sh"
[ -n "${SG_CIBLE:-}" ]   || die "SG_CIBLE manquant : lancez 03_security_groups.sh"

# 1) AMI Amazon Linux 2023 (la plus récente)
log "Recherche de l'AMI Amazon Linux 2023…"
AMI_ID="$(aws ec2 describe-images --region "$REGION" --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" --output text)"
[ "$AMI_ID" != "None" ] || die "AMI AL2023 introuvable."
ok "AMI = $AMI_ID"

# Fonction de lancement (gère proprement le plafond de vCPU du compte partagé)
run_instance() { # $1=nom-tag  $2=sg  $3=--associate.../--no-associate...
  aws ec2 run-instances --region "$REGION" --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" --security-group-ids "$2" "$3" --count 1 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$1}]" \
    --query "Instances[0].InstanceId" --output text 2>&1
}

# 2) Bastion (AVEC IP publique) 
log "Lancement de $TAG_BASTION ($INSTANCE_TYPE, IP publique)…"
BASTION_ID="$(run_instance "$TAG_BASTION" "$SG_BASTION" --associate-public-ip-address)"
echo "$BASTION_ID" | grep -q '^i-' || die "Échec lancement bastion : $BASTION_ID
(Si 'VcpuLimitExceeded' : le compte partagé a atteint son plafond de vCPU,
 réessayez quand un autre étudiant arrête une instance, ou INSTANCE_TYPE=t2.micro.)"
state_set BASTION_ID "$BASTION_ID"
ok "td-bastion = $BASTION_ID"

# 3) Cible (SANS IP publique) 
log "Lancement de $TAG_CIBLE ($INSTANCE_TYPE, SANS IP publique)…"
CIBLE_ID="$(run_instance "$TAG_CIBLE" "$SG_CIBLE" --no-associate-public-ip-address)"
echo "$CIBLE_ID" | grep -q '^i-' || die "Échec lancement cible : $CIBLE_ID
(Voir remarque vCPU ci-dessus.)"
state_set CIBLE_ID "$CIBLE_ID"
ok "td-cible   = $CIBLE_ID"

# 4) Attente 'running' + récupération des adresses 
log "Attente de l'état 'running'…"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$BASTION_ID" "$CIBLE_ID"

BASTION_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$BASTION_ID" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"
CIBLE_PRIV="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$CIBLE_ID" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)"
state_set BASTION_IP "$BASTION_IP"
state_set CIBLE_PRIV "$CIBLE_PRIV"

aws ec2 describe-instances --region "$REGION" --instance-ids "$BASTION_ID" "$CIBLE_ID" \
  --query "Reservations[].Instances[].{Nom:Tags[?Key=='Name']|[0].Value,Id:InstanceId,Etat:State.Name,IpPublique:PublicIpAddress,IpPrivee:PrivateIpAddress}" \
  --output table

ok "Bastion (public) : $BASTION_IP   |   Cible (privée) : $CIBLE_PRIV"
warn "Vérifiez que la cible n'a PAS d'IP publique (colonne IpPublique vide)."
ok "Partie 3 terminée."
