## Projet
Application de messagerie de type WhatsApp, pour de vrais utilisateurs (une dizaine au départ). Le cahier des charges complet est dans `docs/cahier-des-charges.md` : lis-le avant toute tâche importante et ne t'en écarte pas sans le signaler.

## Structure du dépôt (monorepo autour du projet Skip « Telegraphe »)
- Racine : projet Skip existant (Fuse), SwiftUI, iOS 17+ et Android. `Package.swift` déclare les cibles, `Skip.env` porte le nom et l'identifiant de l'app.
- `Sources/Telegraphe/` : UI SwiftUI (`ContentView.swift`, `TelegrapheApp.swift`, `ViewModel.swift`), chaînes dans `Resources/Localizable.xcstrings`.
- `Sources/TelegrapheCore/` (à créer) : module partagé, **sans import de SwiftUI ni UIKit** (modèles, repositories, synchronisation, transport, authentification). Tests dans `Tests/TelegrapheCoreTests/`.
- `Darwin/` et `Android/` : enveloppes de plateforme. `Main.swift` et `Main.kt` ne contiennent que le point d'entrée, aucune logique. Permissions : `Darwin/Info.plist` et `Android/app/src/main/AndroidManifest.xml`. Ne jamais éditer à la main `Telegraphe.xcodeproj`.
- `server/` : Node.js + TypeScript (gateway WebSocket, API REST, worker de notifications).
- `proto/` : fichier `.proto` unique, source des types Swift et TypeScript.
- `infra/` : Docker Compose, configuration Caddy, scripts de sauvegarde.
- `docs/` : cahier des charges, décisions d'architecture (`docs/adr/`).

## Règles d'architecture (non négociables)
1. La base locale SQLite (SkipSQL) est la source de vérité du client. L'UI observe la base, jamais le réseau directement.
2. Envoi par outbox : écrire le message en base avec le statut « en attente », puis envoyer avec retry exponentiel. L'identifiant du message est un UUIDv7 généré côté client (idempotence).
3. Machine à états des messages : en attente → envoyé → livré → lu, plus « échec ».
4. Concurrence côté client : Swift concurrency et acteurs (connexion WebSocket, base de données).
5. Temps réel : WebSocket binaire + Protobuf. Le reste (inscription, profil, groupes, URLs de médias, jeton FCM) : REST/HTTPS.
6. Toute enveloppe contient `type`, `client_id`, `timestamp`, `conversation_id`, `sender_device_id`, `encryption_version`, `payload`. `encryption_version = 0` en v1 (pas de chiffrement).
7. Un `device_id` existe partout dès le départ, même avec un seul appareil par utilisateur.
8. Le serveur est sans état (état dans PostgreSQL/Redis). Le routage entre instances passe par une interface (implémentation Redis pub/sub).
9. Boîte aux lettres : messages stockés pour les destinataires hors ligne, avec un curseur par appareil, supprimés après accusé de réception.
10. Présence et « en train d'écrire » : Redis avec TTL uniquement, jamais en base.
11. Les notifications push ne contiennent jamais le contenu d'un message : c'est un signal de réveil. FCM pour Android uniquement en v1 ; l'iOS (APNs) viendra plus tard derrière la même interface.

## Hors périmètre v1 : ne pas implémenter
Chiffrement de bout en bout, multi-appareils (hors `device_id`), appels, stories, sondages, découverte par numéro de téléphone, APNs. Prévoir les points d'extension, sans coder la fonctionnalité.

## Conventions
- Swift : SwiftLint, noms en anglais, interface utilisateur en **français uniquement** (chaînes dans un catalogue de localisation, jamais en dur).
- TypeScript : mode strict, ESLint + Prettier, validation des entrées (zod ou équivalent), pas de `any`.
- Migrations de base de données versionnées, jamais de modification d'une migration déjà appliquée.
- Commits au format Conventional Commits ; une fonctionnalité par PR.
- Aucune donnée sensible dans les logs (pas de contenu de message, pas de mot de passe, pas de jeton).
- Les secrets viennent de variables d'environnement ; jamais de secret dans le dépôt. Fournir un `.env.example`.
- Mots de passe : argon2id. Jetons : accès court (JWT) + rafraîchissement révocable, par appareil.
- Limitation de débit sur inscription, connexion, envoi et upload.

## Compatibilité Skip / Android
- Avant d'ajouter une dépendance Swift dans `TelegrapheCore`, vérifier qu'elle compile pour Android avec Skip Fuse ; sinon proposer une alternative et le signaler.
- Dans `Sources/Telegraphe/` (Skip Fuse), ne jamais déclarer `private` ni `fileprivate` : les vues SwiftUI (`struct ... : View`) et les propriétés `@State`, `@Binding`, `@Environment`, `@StateObject`, `@Observable` ne peuvent pas être « bridgées » vers Android si elles sont privées (avertissement « cannot be bridged to Android »). Les déclarer `internal` (sans mot-clé).
- Éviter les API réservées à Apple dans `TelegrapheCore` ; isoler ce qui est spécifique à une plateforme derrière un protocole.

## Tests
- `TelegrapheCore` : tests unitaires (outbox, machine à états, synchronisation).
- `server/` : Vitest, tests d'intégration avec PostgreSQL/Redis en conteneurs.
- Chaque fonctionnalité livre ses tests. Lancer lint et tests avant de déclarer une tâche terminée.

## Façon de travailler
- Travaille par petites étapes vérifiables, une phase du plan à la fois (voir `docs/cahier-des-charges.md`, section 7).
- Si une consigne est ambiguë ou contredit le cahier des charges, pose la question avant de coder.
- Ne choisis pas une nouvelle dépendance importante sans la justifier en une phrase (compatibilité Android, maintenance, licence).
- À la fin d'une tâche : résume ce qui a changé, ce qui reste, et les décisions prises (ajoute un ADR court si elle est structurante).