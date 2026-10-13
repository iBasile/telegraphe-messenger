# ADR 005 — Groupes et fan-out

## Décision

Les groupes sont des conversations persistées avec une table de membres et un rôle
`admin` ou `member`. Les droits sont vérifiés par le serveur avant chaque mutation.
Un message de groupe est copié dans la boîte aux lettres de chaque membre, puis
routé vers son appareil connecté. Le retrait purge les messages en attente de ce
groupe pour le membre retiré.

Les changements de membres et de nom sont diffusés comme enveloppes système. La
valeur `encryption_version` reste à `0` en v1.

## Conséquences

- Le gateway reste sans état et fonctionne avec plusieurs instances via le routeur
  existant.
- L'interface client peut afficher un expéditeur et des accusés agrégés sans
  connaître la liste serveur des membres comme source de vérité.
- Les événements système restent des messages de conversation et sont stockés
  localement par `TelegrapheCore`.
