# TD Jour 1 — Sécuriser un réseau AWS

> **Mastère Cybersécurité · 5ᵉ année · IPSSI — AWS Academy (Édition 2026)**
> Sécuriser un réseau AWS : VPC, EC2, Security Groups & NACL.

Ce dépôt automatise l'intégralité du TD à l'aide de scripts **Bash + AWS CLI**, un par
étape. Chaque script est court, commenté, et indique à quelle partie du TD il correspond.

- 📄 Le **livrable** (schéma, réponses aux questions, bonnes pratiques) : [`COMPTE_RENDU.md`](COMPTE_RENDU.md)
- ⚙️ Région de travail : **eu-west-3 (Paris)** · VPC par défaut `172.31.0.0/16`

---

## 🎯 Objectif du TD

Apprendre à sécuriser un réseau dans le cloud en construisant une architecture
**bastion / serveur protégé**, puis en empilant deux niveaux de pare-feu :

```
        Internet
           │  SSH (port 22) autorisé UNIQUEMENT depuis mon IP
           ▼
   ┌───────────────────────────────────────────────┐
   │ Sous-réseau public (route 0.0.0.0/0 → Internet) │
   │                                                 │
   │   ┌──────────────┐   SSH / ping   ┌───────────┐ │
   │   │  td-bastion  │ ─────────────► │ td-cible  │ │
   │   │  IP publique │                │ sans IP   │ │
   │   │              │                │ publique  │ │
   │   └──────────────┘                └───────────┘ │
   │   Accès : depuis mon IP            Accès : depuis│
   │                                    le bastion    │
   └───────────────────────────────────────────────┘

  • Le bastion = porte d'entrée (seule machine joignable d'Internet).
  • La cible = serveur protégé (aucune IP publique → inaccessible directement).
  • Security Group  : pare-feu de l'instance (stateful).
  • NACL            : pare-feu du sous-réseau (stateless).
```

---

## ✅ Prérequis

| Outil | Vérifier avec | Remarque |
|-------|---------------|----------|
| AWS CLI v2 configurée | `aws sts get-caller-identity` | accès EC2 + VPC dans `eu-west-3` |
| Client SSH | `ssh -V` | inclus dans Git Bash / OpenSSH |
| Bash + curl | `bash --version` | **Git Bash** sous Windows |

> 💡 Sous Windows, lancez **Git Bash** (pas PowerShell) : les scripts sont écrits en Bash.

---

## 🚀 Démarrage rapide

```bash
cd aws-td-jour1

# 1. Préparation et infrastructure
bash 01_prerequis.sh          # IP publique + paire de clés SSH
bash 02_explore_vpc.sh        # explore le VPC par défaut
bash 02b_creer_subnet.sh      # (option) crée son sous-réseau dédié, visible en console
bash 03_security_groups.sh    # crée les deux pare-feu (Security Groups)
bash 04_lancer_ec2.sh         # lance le bastion + la cible

# 2. Vérification
bash 05_tests_connectivite.sh # 3 tests : SSH bastion, ping cible, rebond bastion→cible

# 3. Pare-feu de sous-réseau (NACL)
export TD_CONFIRM_NACL=yes     # confirmation requise (voir avertissement plus bas)
bash 06_nacl.sh                # NACL stateless + ports éphémères
bash 07_defense_profondeur.sh  # NACL + SG : le plus restrictif l'emporte

# 4. Nettoyage (OBLIGATOIRE — les instances sont facturées tant qu'elles tournent)
bash 08_nettoyage.sh
```

---

## 📂 Les scripts

| Script | Partie TD | Rôle |
|--------|:---------:|------|
| `00_config.sh` | — | Variables communes + état partagé (sourcé par les autres) |
| `01_prerequis.sh` | 1 | Récupère l'IP publique et crée la paire de clés EC2 |
| `02_explore_vpc.sh` | 2 | Explore le VPC par défaut et choisit un sous-réseau public |
| `02b_creer_subnet.sh` | 2 *(option)* | Crée un sous-réseau dédié `td-subnet-dany` + sa table de routage |
| `03_security_groups.sh` | 4 | Crée `sg-bastion` (SSH ← mon IP) et `sg-cible` (SSH+ICMP ← bastion) |
| `04_lancer_ec2.sh` | 3 | Lance le bastion (avec IP publique) et la cible (sans IP publique) |
| `05_tests_connectivite.sh` | 4 | Tests SSH / ping prouvant le comportement *stateful* des SG |
| `06_nacl.sh` | 5 | NACL *stateless* : illustre le piège des ports éphémères |
| `07_defense_profondeur.sh` | 6 | Combine NACL + SG : le filtre le plus restrictif gagne |
| `08_nettoyage.sh` | 7 | Supprime **uniquement** les ressources créées |

> Les Security Groups (Partie 4) sont créés **avant** les instances (Partie 3) afin de
> les attacher dès le lancement : l'ordre d'exécution diffère donc légèrement de la
> numérotation du TD, mais chaque script précise la partie concernée.

---

## 🔍 Comment vérifier que tout fonctionne

**Test automatique :**

```bash
bash 05_tests_connectivite.sh
```

Résultat attendu — trois lignes `[OK]` :
1. **SSH vers le bastion** réussi → le Security Group autorise bien votre IP.
2. **ping bastion → cible** réussi → la cible accepte le trafic du bastion.
3. **SSH bastion → cible** réussi → la cible n'est joignable **que** via le bastion.

**Test de sécurité (preuve que la protection marche)** — cette commande **doit échouer** :

```bash
# Tenter d'atteindre la cible directement depuis votre PC : doit rester bloqué (timeout)
ssh -i .keys/cle-td-dany.pem -o ConnectTimeout=8 ec2-user@<IP_PRIVEE_CIBLE>
```

Un timeout ici est le résultat **attendu** : sans IP publique, la cible est injoignable
depuis Internet.

---

## ⚠️ Points de vigilance

- **VPC partagé** — Ne jamais modifier les ressources des autres étudiants. Le nettoyage
  supprime les ressources par leur **ID** (jamais par nom/tag, car les noms `td-bastion` /
  `td-cible` sont réutilisés par tout le monde).
- **NACL = niveau sous-réseau** — Une NACL s'applique à *tout* le sous-réseau. Le script
  `06_nacl.sh` reste donc bloqué tant que vous n'avez pas exporté `TD_CONFIRM_NACL=yes`.
  L'association d'origine est sauvegardée puis rétablie au nettoyage.
- **SSH jamais ouvert à tous** — La source autorisée pour le port 22 est `VOTRE_IP/32`,
  jamais `0.0.0.0/0`.
- **Facturation** — Les instances EC2 sont facturées tant qu'elles tournent. Lancez
  `08_nettoyage.sh` dès que le TD est terminé.
- **Plafond de vCPU** — Le compte AWS Academy partagé est limité (≈ 32 vCPU). En cas
  d'erreur `VcpuLimitExceeded`, attendez qu'un vCPU se libère ou utilisez `t2.micro`.

---

## 🛠️ Personnalisation

Toutes les options se règlent par variables d'environnement (avant de lancer les scripts) :

```bash
export TD_PREFIX=dany           # préfixe de vos ressources (défaut : dany)
export INSTANCE_TYPE=t2.micro   # type d'instance (secours si plafond vCPU atteint)
export SUBNET_ID=subnet-xxxx    # forcer un sous-réseau précis
```

---

## 🔐 Sécurité du dépôt

Le fichier [`.gitignore`](.gitignore) empêche de publier :

- `.keys/` et `*.pem` — la **clé privée SSH** ;
- `.td-state.env` — les identifiants de ressources générés.

**Aucun secret n'est versionné** : le dépôt peut être poussé sur GitHub sans risque.
