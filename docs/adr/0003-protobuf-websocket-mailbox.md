# ADR 0003 : Protocole binaire et boîte aux lettres

## Décision

Les messages 1:1 transitent par une enveloppe Protobuf unique sur WebSocket.
La gateway authentifie le JWT avant la poignée de main de version, persiste
chaque enveloppe dans PostgreSQL pour le `device_id` destinataire, puis la
route via une interface `MessageRouter`. Redis pub/sub est l'implémentation
utilisée en production.

La contrainte unique `(recipient_device_id, client_id)` assure l'idempotence.
Le curseur PostgreSQL est avancé et les lignes supprimées lors de l'accusé
`DELIVERED`. L'accusé `READ` contient explicitement le `target_device_id`,
car le message source peut déjà avoir été supprimé de la boîte aux lettres.

## Contexte

Le serveur doit rester sans état local durable, fonctionner avec plusieurs
instances et permettre le rattrapage après une coupure réseau, sans chiffrer
les messages en v1.

## Conséquences

La présence et la frappe restent exclusivement éphémères dans Redis avec TTL.
Les clients doivent dédupliquer par `client_id` et renvoyer la même enveloppe
en cas d'incertitude sur l'accusé serveur.
