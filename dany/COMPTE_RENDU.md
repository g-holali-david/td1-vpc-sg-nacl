# Compte rendu — TD Jour 1 : Sécuriser un réseau AWS

**Formation :** Sécurité appliquée au Cloud · Mastère Cybersécurité 5ᵉ année · IPSSI — AWS Academy 2026
**Région :** eu-west-3 (Paris) · **VPC par défaut :** `172.31.0.0/16`

---

## 1. Schéma logique de l'architecture

```
                    Internet
                       |
                       |  SSH (22) depuis VOTRE_IP/32 uniquement
                       v
        +----------------------------------------------+
        |  VPC par defaut  172.31.0.0/16               |
        |  Internet Gateway (igw-...)                  |
        |                                              |
        |   Sous-reseau PUBLIC (route 0.0.0.0/0 -> IGW)|
        |   +----------------------------------------+ |
        |   |  [NACL] filtre au niveau SOUS-RESEAU   | |
        |   |                                        | |
        |   |   +-------------+      +-------------+ | |
        |   |   | td-bastion  | SSH  |  td-cible   | | |
        |   |   | IP publique |----->| SANS IP pub | | |
        |   |   | sg-bastion  | +ICMP|  sg-cible   | | |
        |   |   +-------------+      +-------------+ | |
        |   |   SG: SSH<-VOTRE_IP/32  SG: SSH+ICMP   | |
        |   |                         <- src         | |
        |   |                            sg-bastion  | |
        |   +----------------------------------------+ |
        +----------------------------------------------+

Chemin d'acces :  Poste admin --SSH--> bastion --SSH/ICMP--> cible
La cible n'a pas d'IP publique : injoignable directement depuis Internet.
Defense en profondeur : un paquet franchit d'abord la NACL (sous-reseau),
puis le Security Group (instance).
```

---

## 2. Réponses aux questions

### Partie 1 — Le VPC par défaut

**1. Quelle est la plage d'adresses du VPC par défaut, et pourquoi ses sous-réseaux sont-ils « publics » ?**
La plage est **`172.31.0.0/16`**. Ses sous-réseaux sont qualifiés de *publics* parce que leur
table de routage contient une route **`0.0.0.0/0 → Internet Gateway (igw-…)`**. Toute instance
qui y possède une **IP publique** est donc directement joignable depuis Internet (et peut en sortir).

**2. Sans sous-réseau privé, comment rendre une instance injoignable depuis Internet ?**
En **ne lui attribuant pas d'IP publique**. Sans adresse publique, aucune route entrante depuis
Internet ne peut l'atteindre (l'IGW ne traduit que les IP publiques). L'instance ne communique
alors qu'au sein du VPC, via son IP privée `172.31.x.x`.

### Partie 2 — Les deux instances

**1. Les deux instances sont dans un sous-réseau public : laquelle est joignable depuis Internet, et pourquoi ?**
Seul le **bastion**, car il possède une **IP publique** et le sous-réseau route vers l'IGW.
La **cible** n'a pas d'IP publique : bien que dans le même sous-réseau public, elle reste
inaccessible depuis l'extérieur.

**2. Comment atteindre la cible puisqu'elle n'a pas d'IP publique ?**
Par **rebond via le bastion** (*bastion host*) : on se connecte en SSH au bastion (IP publique),
puis depuis le bastion on atteint la cible par son **IP privée** `172.31.x.x` (les deux sont dans
le même VPC). En pratique : `ssh -J ec2-user@BASTION ec2-user@IP_PRIVEE_CIBLE`.

### Partie 3 — Security Groups (stateful)

**1. Pourquoi définir la source du `sg-cible` comme `sg-bastion` plutôt qu'une plage d'IP ?**
Parce que la règle devient **dynamique et basée sur l'identité logique**, pas sur l'adressage :
peu importe l'IP privée/publique du bastion, son redémarrage ou un changement d'instance, la
règle « autoriser depuis le groupe `sg-bastion` » reste valable. C'est plus robuste, plus lisible
et conforme au **moindre privilège** (on autorise « les machines du rôle bastion », pas une IP figée).

**2. Vous n'avez autorisé que l'entrée SSH ; pourquoi la réponse repart-elle sans règle de sortie explicite ?**
Parce qu'un Security Group est **stateful** : il mémorise les connexions entrantes autorisées et
laisse repartir **automatiquement** le trafic retour associé, sans règle de sortie dédiée
(par ailleurs, le SG autorise par défaut tout le trafic sortant).

### Partie 4 — NACL (stateless)

**1. Vous vous connectez au port 22 : pourquoi autoriser en sortie la plage 1024–65535 et non le port 22 ?**
Parce que le **trafic retour** ne repart pas du port 22. Le client ouvre une connexion *vers* le
port 22 du serveur, mais avec un **port source éphémère** (1024–65535). La réponse du serveur est
donc émise **vers ce port éphémère** du client. La NACL étant **stateless** (elle ne mémorise rien),
il faut autoriser explicitement, en sortie, la plage des ports éphémères — sinon la réponse est
bloquée et la session SSH ne s'établit jamais.

**2. En une phrase, la différence de comportement entre un Security Group et une NACL ?**
Le **Security Group** est *stateful* et s'applique à l'**instance** (règles `allow` seulement, retour
autorisé automatiquement) ; la **NACL** est *stateless* et s'applique au **sous-réseau** (chaque sens
doit être autorisé explicitement, règles `allow` **et** `deny` évaluées dans l'ordre des numéros).

### Partie 5 — Défense en profondeur

**1. Si le SG autorise un flux mais que la NACL le refuse, le trafic passe-t-il ? Pourquoi ?**
**Non.** La NACL (niveau sous-réseau) est évaluée **avant** le Security Group : un `deny` au niveau
du sous-réseau bloque le paquet avant qu'il n'atteigne l'instance. **Le filtre le plus restrictif
l'emporte** ; il faut que **les deux couches** autorisent le flux pour qu'il passe.

**2. Citez un avantage concret d'avoir deux couches de filtrage plutôt qu'une seule.**
La **défense en profondeur** : si une couche est mal configurée ou contournée (ex. un SG ouvert
par erreur), l'autre peut encore bloquer. La NACL permet en outre un **blocage large au niveau
sous-réseau** — par exemple interdire une IP/un préfixe malveillant pour **toutes** les instances
d'un coup — indépendamment des SG attachés à chaque instance.

---

## 3. Conclusion — Bonnes pratiques de sécurité réseau retenues

1. **Moindre privilège** : n'ouvrir que les ports strictement nécessaires, avec des sources
   restreintes. **SSH jamais en `0.0.0.0/0`** mais en `VOTRE_IP/32`.
2. **Architecture bastion** : pas d'IP publique sur les serveurs sensibles ; accès par rebond
   via un point d'entrée unique et contrôlé.
3. **Référencer les SG entre eux** (`source = sg-bastion`) plutôt que des plages d'IP : règles
   stables, basées sur le rôle, qui suivent les machines.
4. **Défense en profondeur** : combiner NACL (sous-réseau, stateless) et SG (instance, stateful) ;
   la NACL est évaluée en premier et le plus restrictif gagne.
5. **Maîtriser stateful vs stateless** : avec une NACL, toujours penser au **trafic retour**
   (ports éphémères 1024–65535).
6. **Hygiène des ressources** : nommer/tagguer ses ressources, supprimer par **ID** (pas par tag
   en environnement partagé) et **nettoyer** systématiquement après usage.

---

## 4. Note d'exécution

Le TD a été automatisé via l'AWS CLI (scripts de ce dépôt). Le sous-réseau public le **moins peuplé**
est choisi automatiquement afin de limiter l'impact de la NACL en environnement partagé.
La connexion SSH au bastion a été validée (`sg-bastion` opérationnel). Le compte AWS Academy étant
partagé et plafonné en vCPU, le lancement de la seconde instance peut nécessiter d'attendre qu'un
vCPU se libère (géré dans `04_lancer_ec2.sh`). Toutes les ressources créées sont supprimées par
`08_nettoyage.sh` (instances, Security Groups, NACL perso + rétablissement de la NACL par défaut,
paire de clés), **sans jamais toucher** au VPC par défaut, à ses sous-réseaux ni à son Internet Gateway.
