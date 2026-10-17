# ADR 0008 : conversations 1:1 et distribution par appareil

## Contexte

Le protocole doit fonctionner avec plusieurs appareils pour un même destinataire,
sans exposer la liste de ses appareils au client émetteur. La boîte aux lettres
reste partitionnée par appareil afin de conserver un curseur indépendant.

## Décision

- `recipient_user_id` est la seule information de routage fournie par le client.
- `recipient_device_id` reste un champ Protobuf optionnel et déprécié pour la
  compatibilité binaire, mais il est ignoré par la gateway.
- La gateway interroge les appareils actifs du destinataire et écrit une copie
  dans la boîte aux lettres de chaque appareil, puis route chaque copie en
  temps réel ou déclenche sa notification.
- L’identifiant d’une conversation 1:1 est l’UUID déterministe dérivé de la
  paire d’identifiants utilisateur triés lexicographiquement. Il est donc
  identique pour les deux participants et ne dépend d’aucun appareil.
- La recherche utilisateur, lorsqu’elle sera exposée, accepte uniquement une
  égalité exacte sur l’e-mail et ne renvoie que l’identifiant et le nom
  d’affichage.

## Conséquences

Le client n’a pas besoin de connaître ni de sélectionner un appareil
destinataire. Un accusé `DELIVERED` reste associé à l’appareil qui l’a émis,
ce qui permet au serveur d’avancer le curseur de cette seule boîte aux lettres.
Les appareils multiples sont ainsi pris en charge au niveau du transport sans
changer l’identité de la conversation.

## Rattrapage

Le client traite les éléments de boîte aux lettres par identifiant croissant.
Pour chaque élément, il insère d’abord l’enveloppe de façon idempotente, envoie
ensuite `DELIVERED`, puis avance son curseur local. Comme le serveur supprime
tout jusqu’à l’identifiant accusé, aucun accusé d’un élément plus récent n’est
émis tant qu’un élément plus ancien n’a pas été traité.
