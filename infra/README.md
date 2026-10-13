# Infrastructure

La pile de développement et de production est décrite dans
[`docker-compose.yml`](./docker-compose.yml) : serveur HTTP, PostgreSQL, Redis,
SeaweedFS (API S3) et Caddy. Les données sont conservées dans des volumes Docker nommés.

Pour démarrer une instance locale :

```sh
cp .env.example .env
cp seaweedfs/s3.json.example seaweedfs/s3.json
# Remplacer les identifiants S3, mots de passe et JWT_SECRET dans .env et s3.json
docker compose --env-file .env up --build
```

Caddy utilise `DOMAIN` pour son hôte et obtient automatiquement un certificat
TLS pour un domaine public. Pour un développement local, `DOMAIN=localhost`
permet de tester la pile sans exposer de service sur Internet.

## Notifications et supervision

`notification-worker` est séparé de la gateway. Il consomme Redis et envoie
uniquement un signal FCM data (`type=wake`, sans contenu de message). Les
variables `FCM_*` doivent contenir les identifiants du compte de service
Firebase. Le fichier Android `google-services.json` se place dans
`Android/app/`; il est ignoré par Git et doit être téléchargé depuis Firebase
Console pour chaque environnement.

Prometheus scrape `/metrics` et Grafana charge automatiquement le tableau de
bord minimal. En production, publier Grafana uniquement derrière un VPN ou
un reverse proxy authentifié, jamais sur le port public.

## Sauvegarde et restauration

Configurer `BACKUP_DIR` sur un disque différent du volume Docker et conserver
`BACKUP_PASSPHRASE` dans un gestionnaire de secrets. Une sauvegarde quotidienne
chiffre PostgreSQL et SeaweedFS :

```sh
docker compose --env-file .env run --rm server true
./backup.sh
```

La rotation (par exemple 14 jours) doit être assurée par le système de fichiers
ou un job cron. Pour restaurer, arrêter les écritures, puis lancer
`./restore.sh backups/telegraphe-...enc`. Le script déchiffre, restaure le dump
PostgreSQL et remet les objets SeaweedFS en place. Tester chaque sauvegarde avec
`./test-restore.sh backups/telegraphe-...enc`; le test vérifie le dump et
l’archive d’objets sans modifier la production.

## Mise en ligne depuis le domicile

Utiliser un domaine, un enregistrement DNS dynamique pointant vers l’IPv4
publique et rediriger les ports TCP 80/443 vers Caddy. En cas de CGNAT,
utiliser Cloudflare Tunnel à la place de la redirection. Caddy obtient et
renouvelle TLS automatiquement. Les mises à jour se font après sauvegarde :
`docker compose pull && docker compose build --pull && docker compose up -d`.
Surveiller `/health`, les journaux JSON de Docker, l’espace disque, Grafana et
les échecs du job de sauvegarde. Les notifications iOS/APNs ne sont pas
implémentées en v1 : iOS récupère les messages à la réouverture ou via le
WebSocket lorsqu’il est actif.
