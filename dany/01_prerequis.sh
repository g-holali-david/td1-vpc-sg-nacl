#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools

log "Identité AWS utilisée :"
aws sts get-caller-identity --output table

# 1) IP publique du poste 
log "Récupération de votre IP publique (curl checkip.amazonaws.com)…"
MY_IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
[ -n "$MY_IP" ] || die "Impossible de récupérer l'IP publique."
state_set MY_IP "$MY_IP"
state_set MY_CIDR "${MY_IP}/32"
ok "Votre IP : ${MY_IP}  ->  VOTRE_IP/32 = ${MY_IP}/32"

# 2) Paire de clés EC2 
mkdir -p "$KEY_DIR"
if aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  warn "La paire de clés '$KEY_NAME' existe déjà côté AWS."
  if [ ! -f "$KEY_FILE" ]; then
    warn "…mais le .pem local est absent : impossible de l'utiliser pour SSH."
    warn "    -> supprimez la clé AWS et relancez, OU changez KEY_NAME."
  fi
else
  log "Création de la paire de clés '$KEY_NAME'…"
  aws ec2 create-key-pair --region "$REGION" --key-name "$KEY_NAME" \
    --query "KeyMaterial" --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE" 2>/dev/null || true
  # Sous Windows : restreindre l'ACL pour qu'OpenSSH accepte la clé
  if command -v icacls >/dev/null 2>&1; then
    WINKEY="$(cygpath -w "$KEY_FILE" 2>/dev/null || echo "$KEY_FILE")"
    icacls "$WINKEY" /inheritance:r >/dev/null 2>&1 || true
    icacls "$WINKEY" /grant:r "$(whoami):R" >/dev/null 2>&1 || true
  fi
  ok "Clé créée : $KEY_FILE (NON versionnée, voir .gitignore)"
fi

ok "Partie 1 terminée."
