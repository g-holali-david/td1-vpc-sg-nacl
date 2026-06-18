#!/usr/bin/env bash
# =============================================================================
# 05_tests_connectivite.sh  —  TD Partie 4 (suite) : vérifier les SG
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools
[ -f "$KEY_FILE" ]        || die "Clé privée absente ($KEY_FILE)."
[ -n "${BASTION_IP:-}" ]  || die "BASTION_IP manquant : lancez 04_lancer_ec2.sh"
[ -n "${CIBLE_PRIV:-}" ]  || die "CIBLE_PRIV manquant : lancez 04_lancer_ec2.sh"

# Options SSH dans un TABLEAU bash : indispensable car $KEY_FILE peut contenir
# des espaces (ex. "Daniele Obatteba"). Une simple chaîne serait découpée par le
# shell et SSH recevrait un mauvais chemin de clé.
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)

# 1) SSH poste -> bastion (avec quelques tentatives le temps du boot)
log "Test 1 : SSH du poste vers le bastion ($BASTION_IP)…"
for i in $(seq 1 10); do
  if ssh "${SSH_OPTS[@]}" ec2-user@"$BASTION_IP" 'echo OK_BASTION; hostname' 2>/dev/null | grep -q OK_BASTION; then
    ok "SSH vers le bastion réussi (tentative $i) -> sg-bastion valide."
    break
  fi
  [ "$i" -eq 10 ] && die "SSH bastion échoué (instance pas prête ou IP non autorisée)."
  echo "    pas encore prêt… ($i)"; sleep 12
done

# 2) ping bastion -> cible (ICMP)
log "Test 2 : ping du bastion vers la cible ($CIBLE_PRIV)…"
ssh "${SSH_OPTS[@]}" ec2-user@"$BASTION_IP" "ping -c 3 $CIBLE_PRIV" \
  && ok "ICMP autorisé : sg-cible accepte le bastion." \
  || warn "ping KO (laisser ~30s à la cible pour démarrer, puis réessayer)."

# 3) SSH bastion -> cible (rebond via ProxyCommand explicite)
# On n'utilise PAS -J/ProxyJump : il ne propage pas nos options (-o ...) à la
# connexion du rebond, ce qui casse la vérification de clé d'hôte. Un ProxyCommand
# explicite embarque toutes les options (et le chemin de clé entre guillemets).
log "Test 3 : SSH du bastion vers la cible (rebond)…"
PROXY="ssh -i \"$KEY_FILE\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ec2-user@$BASTION_IP"
ssh "${SSH_OPTS[@]}" -o ProxyCommand="$PROXY" ec2-user@"$CIBLE_PRIV" \
  'echo OK_CIBLE; hostname' 2>/dev/null | grep -q OK_CIBLE \
  && ok "SSH bastion -> cible réussi : la cible n'est joignable QUE via le bastion." \
  || warn "SSH vers la cible KO (laisser la cible finir de démarrer, puis réessayer)."

ok "Tests de connectivité (SG stateful) terminés."
