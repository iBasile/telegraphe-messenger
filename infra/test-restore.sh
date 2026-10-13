#!/bin/sh
set -eu

: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
backup="${1:?Usage: test-restore.sh backup-file}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -pass "env:BACKUP_PASSPHRASE" -in "$backup" |
  tar -xzf - -C "$workdir"
test -s "$workdir/postgres.dump"
test -s "$workdir/seaweedfs.tar.gz"
pg_restore --list "$workdir/postgres.dump" >/dev/null
tar -tzf "$workdir/seaweedfs.tar.gz" >/dev/null
printf '%s\n' "Test de restauration réussi: archives lisibles et manifestes valides."
