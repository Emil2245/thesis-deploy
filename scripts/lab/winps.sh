#!/usr/bin/env bash
# Ejecuta un .ps1 en el PC de laboratorio vía SSH (shell remoto = cmd.exe).
set -euo pipefail
KEY="${LAB_KEY:-$HOME/.ssh/tesis-lab}"
HOST="${LAB_HOST:-deltamontero@192.168.1.8}"
f=$(mktemp); trap 'rm -f "$f"' EXIT
{ echo "\$ProgressPreference='SilentlyContinue'"; cat "$1"; } > "$f"
if grep -qiE 'thesis|tesis' "$f"; then echo "ABORT: nombre prohibido en payload" >&2; exit 1; fi
enc=$(iconv -t UTF-16LE "$f" | base64 -w0)
ssh -i "$KEY" -o BatchMode=yes "$HOST" "powershell -NoProfile -NonInteractive -EncodedCommand $enc" | tr -d '\0'
