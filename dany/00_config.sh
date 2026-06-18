#!/usr/bin/env bash

export REGION="${REGION:-eu-west-3}"                 
export NAME_PREFIX="${TD_PREFIX:-dany}"   # préfixe perso (VPC partagé)
export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"    
export KEY_NAME="${KEY_NAME:-cle-td-${NAME_PREFIX}}" # paire de clés EC2


export SG_BASTION_NAME="${NAME_PREFIX}-td-bastion"
export SG_CIBLE_NAME="${NAME_PREFIX}-td-cible"
export TAG_BASTION="td-bastion-${NAME_PREFIX}"
export TAG_CIBLE="td-cible-${NAME_PREFIX}"
export NACL_NAME="${NAME_PREFIX}-td-nacl"

# --- Dossiers / fichiers locaux (NON versionnés, voir .gitignore) 
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONFIG_DIR
export KEY_DIR="${CONFIG_DIR}/.keys"                 # contient le .pem (gitignoré)
export KEY_FILE="${KEY_DIR}/${KEY_NAME}.pem"
export STATE_FILE="${CONFIG_DIR}/.td-state.env"      # IDs des ressources (gitignoré)

state_set() {
  local key="$1" val="$2"
  touch "$STATE_FILE"
  grep -v "^export ${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "export ${key}=\"${val}\"" >> "$STATE_FILE"
}
# Charge l'état existant dans l'environnement courant
load_state() { [ -f "$STATE_FILE" ] && source "$STATE_FILE" || true; }


log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }   # info
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }  # succès
warn() { printf '\033[1;33m[!]\033[0m  %s\n' "$*"; }  # avertissement
die()  { printf '\033[1;31m[X]\033[0m  %s\n' "$*" >&2; exit 1; }

# Vérifie la présence des outils requis
require_tools() {
  command -v aws >/dev/null || die "AWS CLI introuvable."
  command -v ssh >/dev/null || warn "Client SSH introuvable (tests de connexion impossibles)."
}

load_state
