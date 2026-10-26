#!/usr/bin/env bash
# Prueba de restauración del último respaldo de S3 en una base temporal de la misma instancia RDS.
# Corre pg_restore/psql (postgres:18.6-alpine) en la VM aws-lab-1; la contraseña viaja por stdin (nunca en argumentos ni en pantalla).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
SSH="ssh -i ${LAB_KEY:-$HOME/.ssh/tesis-lab} -o BatchMode=yes ubuntu@$FLOCI_IP"
f=$(awsf s3 ls s3://propuestas-backups/db/ | awk '{print $4}' | tail -1)
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
awsf s3 cp "s3://propuestas-backups/db/$f" "$D/b.dump" --quiet
scp -q -i "${LAB_KEY:-$HOME/.ssh/tesis-lab}" "$D/b.dump" "ubuntu@$FLOCI_IP:/tmp/b.dump"
awsf secretsmanager get-secret-value --secret-id propuestas/db --query SecretString --output text | jq -r .password \
| $SSH 'read -r PGPASSWORD; export PGPASSWORD
PQ() { docker run --rm --network host -e PGPASSWORD -v /tmp/b.dump:/d/b.dump:ro docker.io/library/postgres:18.6-alpine "$@"; }
C="-h 127.0.0.1 -p 7001 -U propuestas"
PQ psql $C -d propuestas -qc "drop database if exists restore_test" -c "create database restore_test"
PQ pg_restore $C -d restore_test --no-owner /d/b.dump
echo "rubros restaurados: $(PQ psql $C -d restore_test -tAc "select count(*) from rubro")"
echo "rubros en vivo:     $(PQ psql $C -d propuestas -tAc "select count(*) from rubro")"
PQ psql $C -d propuestas -qc "drop database restore_test"; rm -f /tmp/b.dump'
echo "respaldo: $f (restore_test eliminada)"
