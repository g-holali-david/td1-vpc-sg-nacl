# Réponses — TD Jour 1 (VPC / SG / NACL)

## Partie 1 — VPC par défaut
1. **Plage du VPC par défaut :** `172.31.0.0/16`. Ses sous-réseaux sont dits « publics »
   car leur table de routage envoie `0.0.0.0/0` vers une **Internet Gateway**.
2. **Rendre une instance injoignable sans subnet privé :** ne pas lui attribuer d'**IP
   publique** (`--no-associate-public-ip-address`) — sans IP publique, elle n'est pas
   joignable depuis Internet.

## Partie 2 — Instances EC2
1. **Joignable depuis Internet :** le **bastion**, parce que c'est lui qui a une IP publique.
2. **Atteindre la cible :** en passant **par le bastion** (rebond SSH), via l'IP privée
   `172.31.x.x` de la cible.

## Partie 3 — Security Groups
1. **Source = sg-bastion plutôt qu'une IP :** parce que l'IP privée du bastion peut changer.
   Référencer le **groupe** autorise « tout ce qui est dans sg-bastion » de façon stable et
   plus sûre (on suit l'identité, pas l'adresse).
2. **Réponse sans règle de sortie :** le Security Group est **stateful** — il mémorise la
   connexion entrante et autorise automatiquement le trafic retour.

## Partie 4 — NACL
1. **Pourquoi 1024–65535 en sortie et pas le port 22 :** le serveur répond depuis le port 22
   **vers le port éphémère** (1024–65535) choisi par le client. C'est ce trafic retour qu'il
   faut autoriser en sortie.
2. **SG vs NACL (1 phrase) :** le Security Group est **stateful** (au niveau instance) et la
   NACL est **stateless** (au niveau sous-réseau), donc la NACL exige des règles explicites
   pour l'aller **et** le retour.

## Partie 5 — Défense en profondeur
1. **SG autorise mais NACL refuse → le trafic passe-t-il ?** Non. La **NACL est évaluée
   avant** le SG : un refus au niveau sous-réseau bloque le paquet, peu importe le SG.
2. **Avantage de deux couches :** une erreur ou un oubli sur une couche est rattrapé par
   l'autre (défense en profondeur) — il faut franchir **deux** filtres indépendants.

## Conclusion — bonnes pratiques retenues
- Moindre privilège : n'ouvrir que le strict nécessaire (SSH depuis MON IP seulement).
- Jamais de SSH (22) ouvert en `0.0.0.0/0`.
- Référencer des Security Groups comme source plutôt que des plages d'IP.
- Combiner NACL (sous-réseau) + SG (instance) pour la défense en profondeur.
- Nettoyer ses ressources après usage.
