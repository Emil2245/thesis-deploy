#!/usr/bin/env bash
# G7 (plan 040): ensayo de restauración. Baja el ÚLTIMO pg_dump de S3, lo restaura en una base temporal "restore_drill" de la
# misma instancia RDS y compara el conteo de filas de 5 tablas clave con la base en vivo. Sale con 1 si alguna difiere.
# La contraseña viaja por stdin (nunca en argumentos ni en pantalla). Corre postgres:18.6-alpine en la VM aws-lab-1.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
KEY=${LAB_KEY:-$HOME/.ssh/tesis-lab}
SSH="ssh -i $KEY -o BatchMode=yes ubuntu@$FLOCI_IP"
TABLAS="rubro apu apu_detalle insumo actividad"
f=$(awsf s3 ls s3://propuestas-backups/db/ | awk '{print $4}' | sort | tail -1)
[ -n "$f" ] || { echo "no hay respaldos en s3://propuestas-backups/db/" >&2; exit 1; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
awsf s3 cp "s3://propuestas-backups/db/$f" "$D/b.dump" --quiet
scp -q -i "$KEY" "$D/b.dump" "ubuntu@$FLOCI_IP:/tmp/b.dump"
awsf secretsmanager get-secret-value --secret-id propuestas/db --query SecretString --output text | jq -r .password \
| $SSH "bash -s" "$TABLAS" <<'REMOTE'
read -r PGPASSWORD; export PGPASSWORD
TABLAS=$1
PQ() { docker run --rm --network host -e PGPASSWORD -v /tmp/b.dump:/d/b.dump:ro docker.io/library/postgres:18.6-alpine "$@"; }
C="-h 127.0.0.1 -p 7001 -U propuestas"
PQ psql $C -d propuestas -qc "drop database if exists restore_drill" -c "create database restore_drill"
PQ pg_restore $C -d restore_drill --no-owner /d/b.dump
fail=0
printf '%-14s %10s %10s\n' tabla restaurada en_vivo
for t in $TABLAS; do
  a=$(PQ psql $C -d restore_drill -tAc "select count(*) from $t"); b=$(PQ psql $C -d propuestas -tAc "select count(*) from $t")
  printf '%-14s %10s %10s %s\n' "$t" "$a" "$b" "$([ "$a" = "$b" ] && echo OK || echo DIFIERE)"
  [ "$a" = "$b" ] || fail=1
done
PQ psql $C -d propuestas -qc "drop database restore_drill"; rm -f /tmp/b.dump
exit $fail
REMOTE
echo "respaldo restaurado: $f (base restore_drill eliminada)"
