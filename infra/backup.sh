#!/bin/sh
set -eu
umask 077

: "${BACKUP_DIR:?BACKUP_DIR is required}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$BACKUP_DIR"

docker compose exec -T postgres pg_dump --format=custom --no-owner -U "$POSTGRES_USER" "$POSTGRES_DB" > "$workdir/postgres.dump"
docker compose exec -T seaweedfs sh -c "tar -C /data -czf - ." > "$workdir/seaweedfs.tar.gz"
tar -C "$workdir" -czf - postgres.dump seaweedfs.tar.gz |
  openssl enc -aes-256-cbc -pbkdf2 -salt -pass "env:BACKUP_PASSPHRASE" \
  > "$BACKUP_DIR/telegraphe-$timestamp.tar.gz.enc"
printf '%s\n' "Backup chiffrée créée: $BACKUP_DIR/telegraphe-$timestamp.tar.gz.enc"
