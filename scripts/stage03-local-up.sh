#!/usr/bin/env bash
# Local three-app test with dedicated, disposable keys and S3 emulator; no AWS credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
export LOCAL_STAGE03_GID="$(id -g)"
compose=(docker compose -f compose.stage03-local.yaml)
command -v docker >/dev/null && command -v aws >/dev/null && command -v openssl >/dev/null

mkdir -p .local-stage03/user .local-stage03/service
chmod 750 .local-stage03 .local-stage03/user .local-stage03/service
for pair in user service; do
  dir=".local-stage03/$pair"
  if [ ! -f "$dir/privateKey.pem" ] && [ ! -e "$dir/publicKey.pem" ]; then
    (umask 027; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/privateKey.pem" 2>/dev/null)
    openssl rsa -pubout -in "$dir/privateKey.pem" -out "$dir/publicKey.pem" 2>/dev/null
  fi
  [ -s "$dir/privateKey.pem" ] && [ -s "$dir/publicKey.pem" ] || {
    echo "Incomplete local keypair in $dir; refusing to overwrite" >&2; exit 1;
  }
  chmod 640 "$dir/privateKey.pem" "$dir/publicKey.pem"
done

"${compose[@]}" up -d --wait postgres s3 mail
# Explicit loopback endpoint and fake credentials. Never send a command to AWS.
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
endpoint=http://127.0.0.1:14569
case "$endpoint" in http://127.0.0.1:14569) ;; *) exit 1 ;; esac
for attempt in $(seq 1 30); do
  if curl --fail --silent "$endpoint/_floci/health" >/dev/null; then break; fi
  if [ "$attempt" -eq 30 ]; then echo 'Local S3 emulator did not become healthy' >&2; exit 1; fi
  sleep 1
done
if ! aws --endpoint-url "$endpoint" s3api head-bucket --bucket propuestas-stage03-local >/dev/null 2>&1; then
  aws --endpoint-url "$endpoint" s3api create-bucket --bucket propuestas-stage03-local >/dev/null
fi
"${compose[@]}" up -d --build core documentos web
for attempt in $(seq 1 60); do
  if curl --fail --silent http://127.0.0.1:9000/q/health/ready >/dev/null \
    && curl --fail --silent http://127.0.0.1:8081/q/health >/dev/null \
    && curl --fail --silent http://127.0.0.1:8080/healthz >/dev/null; then
    printf 'Local app ready: http://127.0.0.1:8080/ (Core :8082, Documentos :8081)\n'
    exit 0
  fi
  sleep 2
done
echo 'Local app failed to become ready; inspect the three service logs' >&2
exit 1
