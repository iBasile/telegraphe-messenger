# ADR 0009 : SQLite embarqué avec SkipSQLPlus

## Contexte

Le backend `.platform` de SkipSQL dépendait d'une bibliothèque SQLite native
disponible sur iOS mais absente à l'exécution Android. Cette configuration
déclenchait un `fatalError` au démarrage de l'application Android.

## Décision

Telegraphe utilise le produit `SkipSQLPlus` et la configuration
`SQLContext.Configuration.plus` dans `TelegrapheCore`. SkipSQLPlus embarque la
même version de SQLite sur iOS et Android et fournit FTS5. Le chiffrement
SQLCipher reste désactivé en v1.

## Conséquences

La base locale possède le même socle SQLite sur les deux plateformes, au prix
d'une taille d'artefact plus importante. La recherche conserve son repli
`LIKE` si une plateforme ne rend pas FTS5 disponible.
