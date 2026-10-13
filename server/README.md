# Telegraphe server

API REST Fastify/TypeScript du projet Telegraphe. Le serveur utilise PostgreSQL pour les comptes, appareils et sessions. Les mots de passe sont hachés avec **argon2id**; les jetons d'accès JWT sont courts et les jetons de rafraîchissement sont uniquement stockés sous forme de hash.

## Développement

```sh
cp .env.example .env
npm install
npm run migrate
npm run dev
```

`EMAIL_MODE=console` journalise uniquement le destinataire, le sujet et le lien de vérification en développement. Pour SMTP, renseigner `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` et `EMAIL_FROM`. Aucun secret ne doit être commité.

FCM est optionnel pour l'API et les migrations. Laisser `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` et `FCM_PRIVATE_KEY` vides si le worker de notifications n'est pas déployé. Pour activer le worker, renseigner les trois valeurs du compte de service Firebase ; `FCM_CLIENT_EMAIL` doit être une adresse du type `firebase-adminsdk-xxxxx@projet.iam.gserviceaccount.com`, et les sauts de ligne de `FCM_PRIVATE_KEY` doivent être écrits sous la forme `\n` dans le fichier `.env`.

Routes principales: `POST /auth/register`, `POST /auth/verify-email`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `POST /auth/password-reset/request`, `POST /auth/password-reset/confirm`, `GET/PATCH /profile`, `GET /health`.

Les migrations SQL sont versionnées et s'appliquent avec `npm run migrate`; ne jamais modifier une migration déjà déployée. Les tests d'intégration utilisent `DATABASE_URL` et peuvent être lancés avec `npm test`.
