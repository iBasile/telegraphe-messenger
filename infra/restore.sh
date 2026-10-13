#!/bin/sh
set -eu

: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

backup="${1:?Usage: restore.sh backup-file}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -pass "env:BACKUP_PASSPHRASE" -in "$backup" |
  tar -xzf - -C "$workdir"
docker compose exec -T postgres pg_restore --clean --if-exists --no-owner -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$workdir/postgres.dump"
docker compose exec -T seaweedfs sh -c "rm -rf /data/* && tar -C /data -xzf -" < "$workdir/seaweedfs.tar.gz"
printf '%s\n' "Restauration terminée. Vérifier /health et le contenu d'un compte de test."
