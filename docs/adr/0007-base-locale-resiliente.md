# ADR 0007 — Base locale résiliente et recherche optionnelle

## Décision

La base SQLite du client est ouverte dans le répertoire de documents de
l’application, jamais dans le répertoire courant. Le schéma est suivi dans la
table `schema_migrations` et chaque instruction DDL est idempotente
(`IF NOT EXISTS`). Les migrations journalisent le SQL avant exécution et
l’erreur SQLite exacte en cas d’échec.

FTS5 est une optimisation facultative. Si la bibliothèque SQLite de la
plateforme ne fournit pas FTS5, la migration est validée sans les tables
virtuelles et les recherches utilisent `LIKE`. Les données et l’outbox restent
donc disponibles sans FTS5.

Une erreur d’ouverture ou de migration ne provoque pas de crash : l’interface
affiche un état d’erreur en français et permet de réessayer.

## Conséquences

- iOS et Android utilisent chacun le dossier privé de données de l’application.
- Une migration déjà appliquée peut être rejouée sans modifier le schéma.
- Les logs de diagnostic contiennent les instructions SQL de migration et les
  erreurs SQLite, mais aucun contenu de message.
