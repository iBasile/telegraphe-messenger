# ADR 0001 — Socle Skip Fuse

## Résultats

- Le module UI existant utilise `skip.mode: 'native'` ; le Core et ses tests utilisent aussi le mode natif.
- `Package.swift` cible iOS 17 et `Darwin/Telegraphe.xcconfig` fixe `IPHONEOS_DEPLOYMENT_TARGET` à 17.0.
- SkipSQL 0.16.1 compile sur la cible Swift du projet et fournit SQLite avec FTS5 activé.
- SwiftProtobuf 1.38.1 est résolu par SwiftPM ; le Core le référence sans API Apple spécifique.
- Le test Core couvre une migration versionnée, une insertion/lecture et une recherche FTS5.

## Limite de validation

La compilation native du module Core réussit avec `swift build --target TelegrapheCore`, `skip verify`, `skip android build` et le scheme Xcode `TelegrapheCore`. La suite `swift test` du package complet reste bloquée avant l’exécution par les erreurs de duplication de bibliothèques statiques du graphe Skip (`SkipFuseUI`/`SkipFoundation`/`SkipUnit`). Le projet de test est ensuite compilé par `skip test`, mais son harness Gradle Fuse échoue sur la référence générée `swiftBuildFolder` ; ce point relève de l’outillage Skip et n’est pas un échec de compilation de SkipSQL ou de SwiftProtobuf.

## Décision

Conserver Skip Fuse natif, SkipSQL et SwiftProtobuf dans `TelegrapheCore`. Les deux dépendances compilent sur Android via `skip android build`; ne pas ajouter d’alternative SQLite ou Protobuf. Traiter séparément le problème de harness/tests Skip avant d’en faire une porte de qualité CI.
