# Telegraphe

Telegraphe est une application Skip Fuse native pour iOS 17+ et Android. Cette phase met en place le socle du monorepo et le module `TelegrapheCore` ; aucune fonctionnalité de messagerie n’est encore implémentée.

## Prérequis

- macOS avec Xcode 27 et Swift 6.1+
- Skip 1.9.13 (`skip doctor` permet de vérifier l’installation)
- Android Studio, Android SDK/NDK et un Swift Android SDK compatible pour les builds Android
- Un simulateur iOS ou un émulateur Android pour lancer l’application

## Compiler et lancer sur iOS

Ouvrir `Project.xcworkspace` dans Xcode puis lancer le scheme **Telegraphe App**. Pour compiler sans signature :

```sh
xcodebuild -workspace Project.xcworkspace \
  -scheme "Telegraphe App" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

Le scheme **Telegraphe** compile le module UI sans lancer automatiquement Android. Le nom, l’identifiant et la version se configurent dans [Skip.env](Skip.env), pas dans le projet Xcode.

## Compiler et lancer sur Android

Depuis la racine :

```sh
skip android build
```

Pour lancer l’application, démarrer d’abord un émulateur Android dans Android Studio, puis lancer le scheme **Telegraphe App** dans Xcode ou utiliser les tâches Skip/Gradle générées. `skip android build` vérifie la compilation native des modules Skip Fuse, notamment `TelegrapheCore`.

## Tests

```sh
swift test --filter databaseMigrationsPersistenceAndFullTextSearch
skip test
```

Le test du Core couvre les migrations versionnées, l’insertion/lecture SQLite et FTS5. `skip test` exécute le test sur Darwin et Android lorsque la génération Gradle Fuse est disponible.

## Structure

```text
.
├── Package.swift                  # produits Telegraphe et TelegrapheCore
├── Skip.env                       # identité et version de l’application
├── Sources/Telegraphe/             # interface SwiftUI/Compose
├── Sources/TelegrapheCore/         # base locale et logique partagée, sans SwiftUI/UIKit
├── Tests/TelegrapheCoreTests/      # tests SQLite/FTS5 et harness Skip
├── Darwin/                         # enveloppe iOS
├── Android/                        # enveloppe Android
├── server/                         # futur serveur Node.js/TypeScript
├── proto/                          # futur contrat Protobuf unique
├── infra/                          # futur déploiement Docker/Caddy
└── docs/adr/                       # décisions d’architecture
```

La base locale SQLite via SkipSQL est la source de vérité du client. L’écran minimal lit sa liste depuis `TelegrapheCore`; le réseau et la messagerie seront ajoutés dans les phases suivantes.
