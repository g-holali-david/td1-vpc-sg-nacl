#!/usr/bin/env bash
# =============================================================================
# 06_nacl.sh  —  TD Partie 5 : NACL (pare-feu de sous-réseau, STATELESS)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -n "${VPC_ID:-}" ]     || die "VPC_ID manquant (02_explore_vpc.sh)."
[ -n "${SUBNET_ID:-}" ]  || die "SUBNET_ID manquant (02_explore_vpc.sh)."
[ -n "${MY_CIDR:-}" ]    || die "MY_CIDR manquant (01_prerequis.sh)."

[ "${TD_CONFIRM_NACL:-no}" = "yes" ] || die \
"Partie NACL bloquée par sécurité (environnement partagé).
 Prévenez vos camarades, puis relancez avec :  export TD_CONFIRM_NACL=yes"

ssh_test() { # renvoie 0 si SSH au bastion passe, 1 sinon
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 -o BatchMode=yes ec2-user@"$BASTION_IP" 'echo OK' 2>/dev/null | grep -q OK
}

# 1) Sauvegarde de l'association NACL actuelle (pour rétablir ensuite) 
log "Sauvegarde de l'association NACL actuelle du sous-réseau $SUBNET_ID…"
read -r ORIG_ASSOC_ID DEFAULT_NACL_ID < <(aws ec2 describe-network-acls --region "$REGION" \
  --filters Name=association.subnet-id,Values="$SUBNET_ID" \
  --query "NetworkAcls[].Associations[?SubnetId=='$SUBNET_ID'][].[NetworkAclAssociationId,NetworkAclId]" \
  --output text)
[ -n "${ORIG_ASSOC_ID:-}" ] || die "Association NACL d'origine introuvable."
state_set ORIG_ASSOC_ID "$ORIG_ASSOC_ID"
state_set DEFAULT_NACL_ID "$DEFAULT_NACL_ID"
ok "Association d'origine : $ORIG_ASSOC_ID (NACL par défaut $DEFAULT_NACL_ID)"

# 2) Création d'une NACL perso et association au sous-réseau
log "Création de la NACL $NACL_NAME…"
NACL_ID="$(aws ec2 create-network-acl --region "$REGION" --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=$NACL_NAME}]" \
  --query "NetworkAcl.NetworkAclId" --output text)"
state_set NACL_ID "$NACL_ID"

CUR_ASSOC_ID="$(aws ec2 replace-network-acl-association --region "$REGION" \
  --association-id "$ORIG_ASSOC_ID" --network-acl-id "$NACL_ID" \
  --query "NewAssociationId" --output text)"
state_set CUR_ASSOC_ID "$CUR_ASSOC_ID"
ok "NACL $NACL_ID associée au sous-réseau (nouvelle assoc : $CUR_ASSOC_ID)."

# 3) Entrée SSH autorisée, AUCUNE sortie (refus implicite) 
log "Règle ENTRANTE 100 : autoriser TCP 22 depuis $MY_CIDR (aucune sortie)…"
aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$NACL_ID" \
  --rule-number 100 --protocol 6 --port-range From=22,To=22 \
  --cidr-block "$MY_CIDR" --rule-action allow --ingress >/dev/null

warn "Test SSH attendu : BLOQUÉ (le retour part sur un port éphémère non autorisé)."
if ssh_test; then warn "Inattendu : SSH passe."; else ok "SSH bloqué, comme prévu (stateless)."; fi

# 4) Ajout de la sortie sur les ports éphémères 
log "Règle SORTANTE 100 : autoriser TCP 1024-65535 vers 0.0.0.0/0…"
aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$NACL_ID" \
  --rule-number 100 --protocol 6 --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow --egress >/dev/null

sleep 3
log "Nouveau test SSH attendu : PASSE."
if ssh_test; then ok "SSH rétabli : le trafic retour (ports éphémères) est autorisé."
else warn "SSH encore KO (réessayez dans quelques secondes)."; fi

ok "Partie 5 terminée. (Enchaînez 07_defense_profondeur.sh, puis 08_nettoyage.sh)"
