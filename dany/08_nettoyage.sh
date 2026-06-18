#!/usr/bin/env bash
# =============================================================================
# 08_nettoyage.sh  —  TD Partie 7 : Nettoyage (OBLIGATOIRE)
# =============================================================================
set -uo pipefail   # pas de -e : on veut continuer même si une étape est déjà faite
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"
require_tools

# 1) Rétablir la NACL par défaut, puis supprimer la NACL perso 
if [ -n "${CUR_ASSOC_ID:-}" ] && [ -n "${DEFAULT_NACL_ID:-}" ]; then
  log "Rétablissement de la NACL par défaut sur le sous-réseau…"
  NEW_ASSOC="$(aws ec2 replace-network-acl-association --region "$REGION" \
    --association-id "$CUR_ASSOC_ID" --network-acl-id "$DEFAULT_NACL_ID" \
    --query "NewAssociationId" --output text 2>/dev/null)"
  [ -n "$NEW_ASSOC" ] && ok "NACL par défaut rétablie (assoc $NEW_ASSOC)." \
                      || warn "Association déjà rétablie ?"
fi
if [ -n "${NACL_ID:-}" ]; then
  log "Suppression de la NACL perso $NACL_ID…"
  aws ec2 delete-network-acl --region "$REGION" --network-acl-id "$NACL_ID" 2>/dev/null \
    && ok "NACL supprimée." || warn "NACL déjà supprimée ou non supprimable."
fi

# 2) Terminer MES instances (par ID)
INST=""
[ -n "${BASTION_ID:-}" ] && INST="$INST $BASTION_ID"
[ -n "${CIBLE_ID:-}" ]   && INST="$INST $CIBLE_ID"
if [ -n "$INST" ]; then
  log "Terminaison des instances :$INST"
  aws ec2 terminate-instances --region "$REGION" --instance-ids $INST \
    --query "TerminatingInstances[].{Id:InstanceId,Etat:CurrentState.Name}" --output table 2>/dev/null
  log "Attente de l'état 'terminated'…"
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INST 2>/dev/null \
    && ok "Instances terminées." || warn "Attente interrompue."
fi

#3) Supprimer MES Security Groups (après détachement des ENIs) 
[ -n "${SG_CIBLE:-}" ]   && { aws ec2 delete-security-group --region "$REGION" --group-id "$SG_CIBLE"   2>/dev/null && ok "sg-cible supprimé."   || warn "sg-cible déjà supprimé/occupé."; }
[ -n "${SG_BASTION:-}" ] && { aws ec2 delete-security-group --region "$REGION" --group-id "$SG_BASTION" 2>/dev/null && ok "sg-bastion supprimé." || warn "sg-bastion déjà supprimé/occupé."; }

# 4) Supprimer la paire de clés + le .pem local 
aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME" 2>/dev/null \
  && ok "Paire de clés '$KEY_NAME' supprimée côté AWS." || true
if [ -f "$KEY_FILE" ]; then
  command -v icacls >/dev/null 2>&1 && icacls "$(cygpath -w "$KEY_FILE" 2>/dev/null || echo "$KEY_FILE")" /reset >/dev/null 2>&1 || true
  rm -f "$KEY_FILE" && ok "Fichier .pem local supprimé." || warn "Supprimez $KEY_FILE manuellement."
fi

# 5) Supprimer le sous-réseau perso + sa table de routage (si créés par 02b)
if [ "${CREATED_SUBNET:-no}" = "yes" ]; then
  if [ -n "${RT_DANY:-}" ]; then
    log "Dissociation + suppression de la table de routage $RT_DANY…"
    ASSOC="$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RT_DANY" \
      --query "RouteTables[0].Associations[?SubnetId=='${SUBNET_ID:-}'].RouteTableAssociationId|[0]" \
      --output text 2>/dev/null)"
    [ -n "$ASSOC" ] && [ "$ASSOC" != "None" ] && aws ec2 disassociate-route-table --region "$REGION" --association-id "$ASSOC" 2>/dev/null
    aws ec2 delete-route-table --region "$REGION" --route-table-id "$RT_DANY" 2>/dev/null \
      && ok "Table de routage supprimée." || warn "Table de routage déjà supprimée/occupée."
  fi
  if [ -n "${SUBNET_ID:-}" ]; then
    log "Suppression du sous-réseau $SUBNET_ID…"
    aws ec2 delete-subnet --region "$REGION" --subnet-id "$SUBNET_ID" 2>/dev/null \
      && ok "Sous-réseau supprimé." || warn "Sous-réseau déjà supprimé/occupé."
  fi
fi

# 6) Vérification finale + purge de l'état
log "Vérification finale (mes ressources doivent avoir disparu) :"
[ -n "${BASTION_ID:-}${CIBLE_ID:-}" ] && aws ec2 describe-instances --region "$REGION" \
  --instance-ids ${BASTION_ID:-} ${CIBLE_ID:-} \
  --query "Reservations[].Instances[].{Id:InstanceId,Etat:State.Name}" --output table 2>/dev/null

rm -f "$STATE_FILE"
ok "Nettoyage terminé. (Le VPC par défaut et ses composants sont restés intacts.)"
