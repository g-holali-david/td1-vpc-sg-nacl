#!/bin/bash
# Partie 2 - Explorer le VPC par defaut

REGION=eu-west-3

# Le VPC par defaut et sa plage (172.31.0.0/16)
aws ec2 describe-vpcs --region $REGION \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock}" --output table

# Les sous-reseaux par defaut (un par zone) -> note le subnet-id que tu vas utiliser
aws ec2 describe-subnets --region $REGION \
  --filters Name=default-for-az,Values=true \
  --query "Subnets[].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock}" --output table
