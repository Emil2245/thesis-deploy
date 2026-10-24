#!/usr/bin/env bash
# Imprime la URL pública actual del quick tunnel.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/propuestas-lab.yaml}"
kubectl -n tunnel logs deploy/cloudflared | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1
