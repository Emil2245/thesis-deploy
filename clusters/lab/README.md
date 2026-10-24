# Clúster de laboratorio (k3s sobre Hyper-V)

3 VMs Ubuntu 24.04 en el PC de laboratorio (`delta`, 192.168.1.8), k3s `v1.37.1+k3s1`, red externa `LAN`.

| VM | Rol | vCPU / RAM | IP (DHCP) |
|----|-----|-----------|-----------|
| k3s-lab-1 | server | 4 / 12 GB | 192.168.1.9 |
| k3s-lab-2 | agent | 4 / 10 GB | 192.168.1.10 |
| k3s-lab-3 | agent | 4 / 10 GB | 192.168.1.11 |

**Recomendado:** reservas DHCP en el router para estas IPs (los hosts sslip.io dependen de 192.168.1.9).
No reiniciar en frío el PC (VT-x se bloquea; ver runbook).

Uso: `scripts/lab/winps.sh <script.ps1>`, `scripts/lab/render-seeds.sh server|agent <nombre> [ip]`,
`scripts/lab/new-vm.ps1`, `scripts/lab/lab-down.ps1`, `scripts/lab/sync-tags.sh`.
El token k3s vive solo en el portátil (`$WORK/k3s-token`), nunca en git.
Kubeconfig: `~/.kube/propuestas-lab.yaml` (fuera de git).
