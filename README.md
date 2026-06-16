# TD Jour 1 — Sécuriser un réseau AWS (VPC / EC2 / SG / NACL)

Mastère Cybersécurité 5ᵉ année · IPSSI — AWS Academy.

Lab réseau dans le **VPC par défaut** (`172.31.0.0/16`) de la région **`eu-west-3`**.
On place un **bastion** (avec IP publique) et une **cible** (sans IP publique), puis
on verrouille les accès avec des **Security Groups** (stateful) et une **NACL** (stateless).

Tout se fait en **console AWS + AWS CLI** (pas de Terraform).

## Prérequis

- AWS CLI configuré (`aws configure`), région `eu-west-3`
- Une paire de clés EC2 (`cle-td.pem`, `chmod 400`)
- Ton IP : `curl https://checkip.amazonaws.com`

## Scripts (dans l'ordre)

| Script | Partie | Rôle |
|--------|--------|------|
| `00-explore.sh` | 2 | Lister le VPC par défaut et ses sous-réseaux |
| `01-instances.sh` | 3 | Lancer le bastion (IP pub) et la cible (sans IP pub) |
| `02-security-groups.sh` | 4 | Créer sg-bastion / sg-cible et les attacher |
| `03-nacl.sh` | 5 | NACL : montrer le piège des ports éphémères |
| `04-defense.sh` | 6 | Défense en profondeur (règle deny prioritaire) |
| `99-cleanup.sh` | 7 | Nettoyage obligatoire (remet la NACL par défaut, terminate, suppr SG) |

Avant de lancer un script, **édite les variables en haut** (les `XXXX` : `vpc-`, `subnet-`,
`ami-`, `i-`, `sg-`, ton IP…).

```bash
bash 00-explore.sh
```

## ⚠️ Important

- La **NACL impacte tout le sous-réseau partagé** : préviens tes camarades et **remets la
  NACL par défaut à la fin** (`99-cleanup.sh`).
- Ne supprime **jamais** le VPC par défaut, ses sous-réseaux ni son IGW.
- Lance `99-cleanup.sh` à la fin pour éviter les coûts.

## Livrable

Voir `reponses.md` (réponses aux questions parties 1→5) + tes captures d'écran.
