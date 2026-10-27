#!/usr/bin/env bash
# Ensayo de restauracion (plan 041). Un Job efimero baja el ULTIMO pg_dump del bucket S3, lo restaura en un PostgreSQL
# desechable DENTRO del Job (la base en vivo no se toca) y compara el conteo de filas de 5 tablas clave con la base en vivo.
# Sale con 1 si alguna difiere. Las claves van por Secret; nada se imprime.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/vps/lib.sh
usar_kubeconfig
J=restore-drill-$(date +%s)
kubectl -n propuestas apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata: {name: $J}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata: {labels: {app.kubernetes.io/component: backup}}
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, fsGroup: 70, seccompProfile: {type: RuntimeDefault}}
      initContainers:
        - name: bajar-ultimo
          image: docker.io/amazon/aws-cli:2.38.6
          command: ["/bin/sh", "-ec"]
          args:
            - |
              f=\$(aws --endpoint-url "\$S3_ENDPOINT" s3 ls "s3://\$S3_BUCKET/db/" | awk '{print \$4}' | sort | tail -1)
              [ -n "\$f" ] || { echo "no hay respaldos en s3://\$S3_BUCKET/db/"; exit 1; }
              echo "ultimo respaldo: \$f"; echo "\$f" > /work/nombre
              aws --endpoint-url "\$S3_ENDPOINT" s3 cp "s3://\$S3_BUCKET/db/\$f" /work/b.dump --quiet
          env:
            - {name: AWS_DEFAULT_REGION, value: us-east-1}
            - {name: HOME, value: /tmp}
            - {name: S3_ENDPOINT, valueFrom: {secretKeyRef: {name: propuestas-backup-s3, key: endpoint}}}
            - {name: S3_BUCKET, valueFrom: {secretKeyRef: {name: propuestas-backup-s3, key: bucket}}}
            - {name: AWS_ACCESS_KEY_ID, valueFrom: {secretKeyRef: {name: propuestas-backup-s3, key: access-key}}}
            - {name: AWS_SECRET_ACCESS_KEY, valueFrom: {secretKeyRef: {name: propuestas-backup-s3, key: secret-key}}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
          volumeMounts: [{name: work, mountPath: /work}, {name: tmp, mountPath: /tmp}]
      containers:
        - name: restaurar-y-comparar
          image: docker.io/library/postgres:18.6-alpine
          command: ["/bin/sh", "-ec"]
          args:
            - |
              echo "respaldo: \$(cat /work/nombre)"
              initdb -D /tmp/pgd -U postgres --auth=trust >/dev/null
              pg_ctl -D /tmp/pgd -w -o "-c listen_addresses='' -c unix_socket_directories=/tmp" start >/dev/null
              Q() { psql -h /tmp -U postgres -d restore_drill -tAc "\$1"; }
              createdb -h /tmp -U postgres restore_drill
              pg_restore -h /tmp -U postgres -d restore_drill --no-owner /work/b.dump
              for i in \$(seq 1 20); do pg_isready -q -h propuestas-db-rw && break; sleep 3; done
              fail=0
              printf '%-14s %10s %10s\n' tabla restaurada en_vivo
              for t in rubro apu apu_detalle insumo actividad; do
                a=\$(Q "select count(*) from \$t")
                b=\$(psql -h propuestas-db-rw -U "\$DB_USER" -d propuestas -tAc "select count(*) from \$t")
                if [ "\$a" = "\$b" ] && [ "\$a" -gt 0 ]; then r=OK; else r=DIFIERE; fail=1; fi
                printf '%-14s %10s %10s %s\n' "\$t" "\$a" "\$b" "\$r"
              done
              pg_ctl -D /tmp/pgd -m fast stop >/dev/null
              exit \$fail
          env:
            - {name: DB_USER, valueFrom: {secretKeyRef: {name: propuestas-db-app, key: username}}}
            - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: propuestas-db-app, key: password}}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
          volumeMounts: [{name: work, mountPath: /work}, {name: tmp, mountPath: /tmp}]
      volumes: [{name: work, emptyDir: {}}, {name: tmp, emptyDir: {}}]
EOF
# espera a que el Job termine (Complete o Failed)
for _ in $(seq 1 90); do
  s=$(kubectl -n propuestas get job "$J" -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null)
  [ -n "$s" ] && break; sleep 5
done
kubectl -n propuestas logs "job/$J" -c bajar-ultimo 2>/dev/null | head -3 || true
kubectl -n propuestas logs "job/$J" -c restaurar-y-comparar
case "$s" in 1*) echo "ensayo de restauracion: OK"; exit 0;; *) echo "ensayo de restauracion: FALLA" >&2; exit 1;; esac
