#!/usr/bin/env bash
# =============================================================================
# 07_defense_profondeur.sh  —  TD Partie 6 : NACL + Security Group
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -n "${NACL_ID:-}" ] || die "NACL_ID manquant : lancez d'abord 06_nacl.sh."
[ -n "${MY_CIDR:-}" ] || die "MY_CIDR manquant."

ssh_test() {
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 -o BatchMode=yes ec2-user@"$BASTION_IP" 'echo OK' 2>/dev/null | grep -q OK
}

#  1) Règle DENY n°90 (prioritaire sur le ALLOW n°100) 
log "Ajout règle ENTRANTE 90 : DENY TCP 22 depuis $MY_CIDR (numéro < 100)…"
aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$NACL_ID" \
  --rule-number 90 --protocol 6 --port-range From=22,To=22 \
  --cidr-block "$MY_CIDR" --rule-action deny --ingress >/dev/null

sleep 3
warn "Test SSH attendu : REFUSÉ (la NACL refuse, peu importe le SG)."
if ssh_test; then warn "Inattendu : SSH passe."; else ok "Accès refusé par la NACL : défense en profondeur démontrée."; fi

# 2) Retrait de la règle DENY n°90 
log "Retrait de la règle DENY n°90…"
aws ec2 delete-network-acl-entry --region "$REGION" --network-acl-id "$NACL_ID" \
  --rule-number 90 --ingress

sleep 3
log "Nouveau test SSH attendu : PASSE de nouveau."
if ssh_test; then ok "Accès rétabli après retrait du DENY."; else warn "SSH encore KO (réessayez)."; fi

warn "N'OUBLIEZ PAS le nettoyage : 08_nettoyage.sh (rétablit la NACL par défaut)."
ok "Partie 6 terminée."
