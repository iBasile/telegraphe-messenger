# Cahier des charges — Application de messagerie (clone WhatsApp)

Version 1.0 — 10 octobre 2026

## 1. Objectif
Application de messagerie mobile pour de vrais utilisateurs (une dizaine au départ), auto-hébergée sur un serveur à domicile. Deux plateformes à partir d'une seule base de code : iOS 17+ et Android, en SwiftUI avec Skip (Fuse).

## 2. Périmètre de la v1 (MVP)
**Inclus**
- Inscription et connexion par e-mail + mot de passe (vérification d'e-mail, réinitialisation du mot de passe).
- Profil : nom d'affichage, photo.
- Recherche d'un utilisateur par e-mail ou identifiant ; lien d'invitation.
- Conversations 1:1 (texte).
- Groupes : création, nom et photo, ajout/retrait de membres, rôles (admin / membre), quitter un groupe.
- Partage de photos et vidéos (1:1 et groupes) avec miniatures et aperçu.
- Statuts des messages : en attente, envoyé, livré, lu (avec échec explicite et renvoi).
- Mode hors ligne : lecture de l'historique local, envoi mis en file puis retransmis.
- Présence et « en train d'écrire ».
- Notifications push Android (FCM).
- Recherche dans les messages (FTS5).
- Interface en français uniquement.

**Hors v1 (à prévoir dans l'architecture, sans les implémenter)**
- Multi-appareils (mais `device_id` présent dès le départ dans tous les modèles).
- Chiffrement de bout en bout (champ `encryption` dans l'enveloppe, valeur 0 = clair).
- Appels audio/vidéo (LiveKit + TURN) : priorité juste après la v1.
- Stories, sondages, messages éphémères, découverte de contacts par numéro de téléphone.
- Notifications push iOS (voir contraintes).

## 3. Contraintes et décisions
| Sujet | Décision |
|---|---|
| Clients | SwiftUI + Skip Fuse, iOS 17 minimum, Android via Skip |
| Base locale | SQLite via SkipSQL, FTS5, migrations versionnées |
| Serveur | Node.js + TypeScript, npm, un seul langage de serveur |
| Protocole | WebSocket binaire + Protobuf (temps réel) ; REST/HTTPS (le reste) |
| Données serveur | PostgreSQL (comptes, appareils, groupes, boîtes aux lettres), Redis (présence, limitation de débit), MinIO (médias) |
| Hébergement | Serveur à domicile, Docker Compose, reverse proxy avec TLS |
| Sécurité v1 | TLS partout, pas de E2E, mots de passe hachés (argon2id) |
| Compte Apple Developer | Absent : pas d'APNs, pas de TestFlight, signature de développement uniquement |
| Firebase | Projet existant, utilisé pour FCM (Android) |

### Conséquences du choix « pas de compte Apple Developer »
- Pas de notifications push iOS en v1. Sur iOS, les messages arrivent via WebSocket quand l'app est ouverte ou récemment active, et par rattrapage (curseur) à la réouverture.
- Les builds iOS installés sans compte payant expirent au bout de 7 jours.
- Prévoir l'ajout d'APNs plus tard sans refonte : le worker de notifications est un module séparé avec une interface par plateforme.

### Conséquence du choix « sans chiffrement »
Le serveur voit le contenu des messages. Il faut le dire clairement aux utilisateurs et sécuriser le serveur (accès, sauvegardes chiffrées, journaux sans contenu). L'enveloppe protobuf prévoit dès maintenant `encryption_version` pour migrer vers E2E plus tard.

## 4. Architecture

### 4.1 Client
- Base locale = source de vérité unique ; l'UI observe SQLite, jamais le réseau.
- Module Swift `TelegrapheCore` (cible du `Package.swift` racine, dans `Sources/TelegrapheCore/`), sans dépendance à SwiftUI/UIKit : modèles, repositories, synchronisation, transport, authentification. Compile nativement sur Android avec Fuse. L'UI reste dans `Sources/Telegraphe/`.
- Pattern outbox : le message est écrit en base (statut « en attente »), puis un worker l'envoie avec retry exponentiel. Identifiant client UUIDv7 pour l'idempotence.
- Machine à états : en attente → envoyé → livré → lu, plus état « échec ».
- Concurrence : Swift concurrency, un acteur pour la connexion WebSocket, un pour la base.
- Médias : compression et génération de miniature côté client avant envoi ; envoi par URL présignée MinIO ; téléchargement à la demande avec cache disque.

### 4.2 Protocole
- Enveloppe : `type`, `client_id` (UUIDv7), `timestamp`, `conversation_id`, `sender_device_id`, `encryption_version`, `payload`.
- Un fichier `.proto` unique, partagé, qui génère les types Swift (swift-protobuf) et TypeScript (ts-proto).
- Version de protocole dans la poignée de main WebSocket ; refus propre des versions trop anciennes.
- REST : inscription, connexion, rafraîchissement du jeton, profil, groupes (gestion), URLs de médias présignées, enregistrement du jeton FCM.

### 4.3 Backend
- Gateway WebSocket sans état. Une seule instance au départ, mais le routage passe par une interface (implémentation Redis pub/sub) pour permettre plusieurs instances.
- Modèle « boîte aux lettres » : message stocké pour chaque destinataire hors ligne avec un curseur par appareil ; suppression après accusé de réception du destinataire.
- Groupes : distribution en fan-out vers chaque membre ; le serveur est la source de vérité de la liste des membres et des rôles.
- Présence et « en train d'écrire » : éphémères dans Redis avec TTL, jamais en base.
- Worker de notifications séparé : envoi FCM sans contenu de message (signal de réveil + récupération).
- Authentification : mot de passe argon2id, jeton d'accès court (JWT) + jeton de rafraîchissement révocable, un jeton par appareil.
- Limitation de débit : inscription, connexion, envoi de messages, upload.

### 4.4 Données
- PostgreSQL : `users`, `devices`, `sessions`, `conversations`, `conversation_members`, `mailbox`, `push_tokens`, `media`. Migrations versionnées (outil au choix : node-pg-migrate ou Drizzle).
- Redis : présence, limitation de débit, pub/sub.
- MinIO : médias avec expiration automatique (durée à valider) et limites de taille.

### 4.5 Exploitation
- Docker Compose : gateway, worker, PostgreSQL, Redis, MinIO, reverse proxy (Caddy recommandé pour le TLS automatique).
- Exposition depuis le domicile : nom de domaine + DNS dynamique, redirection de ports, ou tunnel (Cloudflare Tunnel). À vérifier : l'opérateur fournit-il une IPv4 publique (sinon CGNAT) ?
- Sauvegardes chiffrées quotidiennes de PostgreSQL et de MinIO vers un second emplacement.
- Logs structurés sans contenu de message ; métriques Prometheus + Grafana après le MVP.

### 4.6 Structure du dépôt
Le projet Skip « Telegraphe » existe déjà ; il reste à la racine du dépôt et on lui ajoute les dossiers serveur.

```
.
├── Package.swift            # cibles : Telegraphe (UI), TelegrapheCore (logique)
├── Skip.env                 # identifiant d'app, nom, version
├── Sources/
│   ├── Telegraphe/          # UI SwiftUI (ContentView, TelegrapheApp, ViewModel…)
│   │   ├── Resources/Localizable.xcstrings   # chaînes en français
│   │   └── Skip/skip.yml
│   └── TelegrapheCore/      # (à créer) modèles, base, outbox, transport, auth
├── Tests/TelegrapheCoreTests/   # (à créer)
├── Darwin/                  # enveloppe iOS : Info.plist, Entitlements, Main.swift
├── Android/                 # enveloppe Android : manifest, build.gradle.kts, Main.kt
├── server/                  # (à créer) Node.js + TypeScript
├── proto/                   # (à créer) fichier .proto unique
├── infra/                   # (à créer) Docker Compose, Caddy, sauvegardes
└── docs/                    # (à créer) cahier des charges, adr/
```

Règles : `Darwin/Sources/Main.swift` et `Android/app/src/main/kotlin/Main.kt` ne sont que des points d'entrée, on n'y met pas de logique. Les permissions iOS vont dans `Darwin/Info.plist`, celles d'Android dans `Android/app/src/main/AndroidManifest.xml`. Le nom d'app et l'identifiant se changent dans `Skip.env`, jamais à la main dans le projet Xcode.

## 5. Exigences non fonctionnelles
- Latence de livraison d'un message texte < 1 s entre deux utilisateurs connectés.
- Aucun doublon après une coupure réseau (idempotence).
- Application utilisable hors ligne en lecture ; envois repris automatiquement.
- Taille maximale par défaut : photo 10 Mo (après compression), vidéo 50 Mo et 60 s (valeurs modifiables).
- Accessibilité de base : Dynamic Type, VoiceOver sur les écrans principaux.

## 6. Tests et qualité
- Core : tests unitaires (Swift Testing/XCTest) sur outbox, machine à états, synchronisation.
- Serveur : Vitest, tests d'intégration avec PostgreSQL/Redis en conteneurs.
- CI GitHub Actions : lint, tests serveur, build du package Core, génération des types protobuf (vérifie qu'ils sont à jour).
- Conventions : SwiftLint, ESLint + Prettier, commits « Conventional Commits », une PR par fonctionnalité.
- Documentation : README, décisions d'architecture courtes dans `docs/adr/`.

## 7. Plan de construction
1. **Socle** : projet Skip `Telegraphe` existant, réorganisation en monorepo (ajout de `server/`, `proto/`, `infra/`, `docs/`), module `TelegrapheCore`, vérification de SkipSQL, swift-protobuf et FTS5 sur Android.
2. **Serveur de base** : Compose, PostgreSQL, authentification, migrations, CI.
3. **Protocole et messagerie 1:1 texte** : `.proto`, gateway WebSocket, boîte aux lettres, curseurs, accusés.
4. **Client Core + UI** : base locale, outbox, écrans d'authentification, liste de conversations, discussion.
5. **Groupes**.
6. **Médias** (photos, vidéos).
7. **Push Android (FCM)**, présence, recherche.
8. **Durcissement et exploitation** : sauvegardes, limitation de débit, métriques.
9. **Ensuite** : appels (LiveKit), APNs (quand un compte Apple Developer sera disponible), chiffrement de bout en bout, multi-appareils.

## 8. Risques
- **Skip Fuse + SkipSQL/protobuf sur Android** : valider tôt la compilation des dépendances (phase 1).
- **Exposition depuis le domicile** : disponibilité, IP, coupures ; prévoir supervision et sauvegardes.
- **Pas de push iOS** : l'expérience iOS en arrière-plan sera limitée en v1.
- **Messages en clair côté serveur** : à communiquer, et à traiter avant d'ouvrir à des utilisateurs hors cercle de confiance.