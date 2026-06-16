#!/bin/bash
# Partie 6 - Defense en profondeur : la NACL est evaluee AVANT le Security Group

REGION=eu-west-3
NACL=acl-0988b7153a7051779   # notre NACL td-nacl-david (creee en Partie 5)
MON_IP=82.96.161.255/32

# Regle DENY n90 (numero plus petit = prioritaire) sur SSH
aws ec2 create-network-acl-entry --region $REGION --network-acl-id $NACL \
  --rule-number 90 --protocol 6 --port-range From=22,To=22 \
  --cidr-block $MON_IP --rule-action deny --ingress

# >>> TESTE : acces REFUSE, meme si le Security Group autorise toujours ton IP <<<

# Retirer la regle deny pour retablir l'acces
aws ec2 delete-network-acl-entry --region $REGION --network-acl-id $NACL \
  --rule-number 90 --ingress
