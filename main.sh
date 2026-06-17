#!/bin/bash
# main.sh - Lab AWS VPC/SG/NACL entierement en FONCTIONS, orchestrees ici.

# Usage :
#   bash main.sh up          # cree TOUT le lab (subnet, route-table, instances, SG, NACL)
#   bash main.sh down        # supprime TOUT (par tag) - idempotent
#   bash main.sh explore     # Partie 2 : lister VPC par defaut + sous-reseaux (lecture seule)
#   bash main.sh info        # afficher les ressources actuelles + IP du bastion
#   bash main.sh nacl-trap   # Partie 5 : demontrer le piege des ports ephemeres (interactif)
#   bash main.sh defense     # Partie 6 : demontrer la regle deny prioritaire (interactif)
#

set -uo pipefail

# ============================ Config ============================
REGION=eu-west-3
OWNER=dany       # suffixe d'identification de TES ressources (compte partage)
KEY=cle-td-david         # NOTRE paire de cles (on possede cle-td-david.pem)
CIDR=172.31.250.0/24     # plage de NOTRE sous-reseau (si "Conflict", change le 3e octet)
AZ=eu-west-3a
TYPE_BASTION=t2.micro    # 1 vCPU (compte partage limite a 32 vCPU au total)
TYPE_CIBLE=t2.micro

# ===================== Helpers de decouverte ====================
vpc_id() {
  aws ec2 describe-vpcs --region "$REGION" \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" --output text
}

igw_id() {
  aws ec2 describe-internet-gateways --region "$REGION" \
    --filters Name=attachment.vpc-id,Values="$(vpc_id)" \
    --query "InternetGateways[0].InternetGatewayId" --output text
}

ami_id() {
  aws ec2 describe-images --region "$REGION" --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
    --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" --output text
}

my_ip() {
  echo "$(curl -s https://checkip.amazonaws.com)/32"
}

subnet_id() {
  aws ec2 describe-subnets --region "$REGION" \
    --filters Name=tag:Name,Values="td-subnet-$OWNER" \
    --query "Subnets[0].SubnetId" --output text
}

rt_id() {
  aws ec2 describe-route-tables --region "$REGION" \
    --filters Name=tag:Name,Values="td-rt-$OWNER" \
    --query "RouteTables[0].RouteTableId" --output text
}

nacl_id() {
  aws ec2 describe-network-acls --region "$REGION" \
    --filters Name=tag:Name,Values="td-nacl-$OWNER" \
    --query "NetworkAcls[0].NetworkAclId" --output text
}

sg_id() {
  aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=group-name,Values="$1" \
    --query "SecurityGroups[0].GroupId" --output text
}

instance_id() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$1" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text
}

# Parties du TP

# Partie 2 - explorer (lecture seule)
explore() {
  echo "### Partie 2 - VPC par defaut ###"
  aws ec2 describe-vpcs --region "$REGION" \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock}" --output table

  echo "### Sous-reseaux du VPC par defaut ###"
  aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$(vpc_id)" \
    --query "Subnets[].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,AutoPubIp:MapPublicIpOnLaunch}" --output table
}

# NOTRE reseau : sous-reseau + table de routage (route 0.0.0.0/0 -> IGW)
net_up() {
  local vpc igw subnet rt
  vpc=$(vpc_id)
  igw=$(igw_id)

  echo "### Sous-reseau + table de routage (VPC=$vpc IGW=$igw) ###"

  subnet=$(aws ec2 create-subnet --region "$REGION" \
    --vpc-id "$vpc" --cidr-block "$CIDR" --availability-zone "$AZ" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=td-subnet-$OWNER}]" \
    --query "Subnet.SubnetId" --output text)

  aws ec2 modify-subnet-attribute --region "$REGION" \
    --subnet-id "$subnet" --map-public-ip-on-launch

  rt=$(aws ec2 create-route-table --region "$REGION" \
    --vpc-id "$vpc" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=td-rt-$OWNER}]" \
    --query "RouteTable.RouteTableId" --output text)

  aws ec2 create-route --region "$REGION" \
    --route-table-id "$rt" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null

  aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$rt" --subnet-id "$subnet" >/dev/null

  echo "subnet=$subnet  rt=$rt"
}

# Partie 3 - instances bastion (IP pub) + cible (sans IP pub)
instances_up() {
  local ami subnet bastion cible
  ami=$(ami_id)
  subnet=$(subnet_id)

  echo "### Instances (AMI=$ami subnet=$subnet) ###"

  bastion=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$ami" --instance-type "$TYPE_BASTION" --key-name "$KEY" \
    --subnet-id "$subnet" --associate-public-ip-address --count 1 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=td-bastion-$OWNER}]" \
    --query "Instances[0].InstanceId" --output text)

  cible=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$ami" --instance-type "$TYPE_CIBLE" --key-name "$KEY" \
    --subnet-id "$subnet" --no-associate-public-ip-address --count 1 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=td-cible-$OWNER}]" \
    --query "Instances[0].InstanceId" --output text)

  echo "bastion=$bastion  cible=$cible  (attente running...)"
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$bastion" "$cible"
}

# Partie 4 - Security Groups (stateful) + attachement
sg_up() {
  local vpc ip sgb sgc bastion cible
  vpc=$(vpc_id)
  ip=$(my_ip)

  echo "### Security Groups (mon IP=$ip) ###"

  sgb=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "td-sg-bastion-$OWNER" --description "SSH bastion" --vpc-id "$vpc" \
    --query GroupId --output text)

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$sgb" --protocol tcp --port 22 --cidr "$ip" >/dev/null

  sgc=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "td-sg-cible-$OWNER" --description "Acces depuis bastion" --vpc-id "$vpc" \
    --query GroupId --output text)

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$sgc" --protocol tcp --port 22 --source-group "$sgb" >/dev/null

  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$sgc" --protocol icmp --port -1 --source-group "$sgb" >/dev/null

  bastion=$(instance_id "td-bastion-$OWNER")
  cible=$(instance_id "td-cible-$OWNER")

  aws ec2 modify-instance-attribute --region "$REGION" --instance-id "$bastion" --groups "$sgb"
  aws ec2 modify-instance-attribute --region "$REGION" --instance-id "$cible"  --groups "$sgc"

  echo "sg-bastion=$sgb  sg-cible=$sgc"
}

# Partie 5 - NACL (stateless) : entree SSH + sortie ports ephemeres
nacl_up() {
  local vpc subnet nacl assoc ip
  vpc=$(vpc_id)
  subnet=$(subnet_id)
  ip=$(my_ip)

  echo "### NACL sur NOTRE sous-reseau ($subnet) ###"

  nacl=$(aws ec2 create-network-acl --region "$REGION" \
    --vpc-id "$vpc" \
    --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=td-nacl-$OWNER}]" \
    --query NetworkAcl.NetworkAclId --output text)

  assoc=$(aws ec2 describe-network-acls --region "$REGION" \
    --filters Name=association.subnet-id,Values="$subnet" \
    --query "NetworkAcls[].Associations[?SubnetId=='$subnet'].NetworkAclAssociationId" --output text)

  aws ec2 replace-network-acl-association --region "$REGION" \
    --association-id "$assoc" --network-acl-id "$nacl" >/dev/null

  # Entree : SSH depuis mon IP
  aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$nacl" \
    --rule-number 100 --protocol 6 --port-range From=22,To=22 \
    --cidr-block "$ip" --rule-action allow --ingress

  # Sortie : ports ephemeres (trafic retour, indispensable en stateless)
  aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$nacl" \
    --rule-number 100 --protocol 6 --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 --rule-action allow --egress

  echo "nacl=$nacl"
}

# Afficher l'etat courant
info() {
  local b c pub priv
  echo "### Etat du lab (-$OWNER) ###"
  echo "VPC        = $(vpc_id)"
  echo "Subnet     = $(subnet_id)    RT = $(rt_id)    NACL = $(nacl_id)"
  echo "SG bastion = $(sg_id "td-sg-bastion-$OWNER")    SG cible = $(sg_id "td-sg-cible-$OWNER")"

  b=$(instance_id "td-bastion-$OWNER")
  c=$(instance_id "td-cible-$OWNER")

  if [ -n "$b" ]; then
    pub=$(aws ec2 describe-instances --region "$REGION" --instance-ids $b \
      --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    echo "Bastion    = $b    IP pub  $pub"
    echo "  SSH : ssh -i ${KEY}.pem ec2-user@$pub"
  fi

  if [ -n "$c" ]; then
    priv=$(aws ec2 describe-instances --region "$REGION" --instance-ids $c \
      --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
    echo "Cible      = $c    IP priv $priv   (rebond depuis le bastion)"
  fi
}

# Tout creer
up() {
  if [ "$(subnet_id)" != "None" ]; then
    echo "Des ressources -$OWNER existent deja. Lance d'abord :  bash main.sh down"
    return 1
  fi
  net_up
  instances_up
  sg_up
  nacl_up
  echo ""
  info
  echo ""
  echo "================= LAB PRET ================="
}

# Tout supprimer (par tag), idempotent
down() {
  local insts="" b c subnet rt nacl sgb sgc
  b=$(instance_id "td-bastion-$OWNER")
  c=$(instance_id "td-cible-$OWNER")
  [ -n "$b" ] && insts="$insts $b"
  [ -n "$c" ] && insts="$insts $c"
  insts=$(echo $insts)

  if [ -n "$insts" ]; then
    echo "Terminate : $insts"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $insts >/dev/null
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids $insts
  fi

  sgc=$(sg_id "td-sg-cible-$OWNER")
  sgb=$(sg_id "td-sg-bastion-$OWNER")
  [ "$sgc" != "None" ] && aws ec2 delete-security-group --region "$REGION" --group-id "$sgc" && echo "SG cible supprime"
  [ "$sgb" != "None" ] && aws ec2 delete-security-group --region "$REGION" --group-id "$sgb" && echo "SG bastion supprime"

  subnet=$(subnet_id)
  nacl=$(nacl_id)
  rt=$(rt_id)
  [ "$subnet" != "None" ] && aws ec2 delete-subnet      --region "$REGION" --subnet-id "$subnet"    && echo "Subnet supprime"
  [ "$nacl"   != "None" ] && aws ec2 delete-network-acl --region "$REGION" --network-acl-id "$nacl" && echo "NACL supprimee"
  [ "$rt"     != "None" ] && aws ec2 delete-route-table --region "$REGION" --route-table-id "$rt"   && echo "Route-table supprimee"

  echo "Nettoyage termine."
}

# Partie 5 (interactif) - le piege des ports ephemeres, sur le lab deja monte
nacl_trap() {
  local nacl
  nacl=$(nacl_id)
  [ "$nacl" = "None" ] && { echo "Aucune NACL : lance d'abord 'bash main.sh up'"; return 1; }

  echo "Retrait de la regle de SORTIE (ports ephemeres)..."
  aws ec2 delete-network-acl-entry --region "$REGION" \
    --network-acl-id "$nacl" --rule-number 100 --egress

  echo ">>> Teste ta connexion SSH au bastion : elle doit etre BLOQUEE (pas de trafic retour)."
  read -r -p "Appuie sur Entree pour retablir la sortie... " _

  aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$nacl" \
    --rule-number 100 --protocol 6 --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 --rule-action allow --egress

  echo ">>> Reteste : la connexion PASSE de nouveau."
}

# Partie 6 (interactif) - regle deny prioritaire (defense en profondeur)
defense() {
  local nacl ip
  nacl=$(nacl_id)
  ip=$(my_ip)
  [ "$nacl" = "None" ] && { echo "Aucune NACL : lance d'abord 'bash main.sh up'"; return 1; }

  echo "Ajout d'une regle DENY n90 (prioritaire) sur SSH..."
  aws ec2 create-network-acl-entry --region "$REGION" --network-acl-id "$nacl" \
    --rule-number 90 --protocol 6 --port-range From=22,To=22 \
    --cidr-block "$ip" --rule-action deny --ingress

  echo ">>> Teste : acces REFUSE, meme si le Security Group autorise toujours ton IP."
  read -r -p "Appuie sur Entree pour retirer la regle deny... " _

  aws ec2 delete-network-acl-entry --region "$REGION" \
    --network-acl-id "$nacl" --rule-number 90 --ingress

  echo ">>> Acces retabli."
}

# =========================== Dispatcher =========================
case "${1:-up}" in
  up)         up ;;
  down)       down ;;
  explore)    explore ;;
  info)       info ;;
  nacl-trap)  nacl_trap ;;
  defense)    defense ;;
  *) echo "Usage: bash main.sh {up|down|explore|info|nacl-trap|defense}"; exit 1 ;;
esac
