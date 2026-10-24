output "server_ipv4" {
  description = "IP publica del nodo server."
  value       = hcloud_primary_ip.server.ip_address
}

output "agent_ipv4s" {
  description = "IPs publicas de los agents."
  value       = hcloud_server.agent[*].ipv4_address
}

output "app_url" {
  value = "https://propuestas.${hcloud_primary_ip.server.ip_address}.sslip.io"
}

output "kubeconfig_cmd" {
  description = "Descarga el kubeconfig (cambia 127.0.0.1 por la IP publica)."
  value       = "ssh root@${hcloud_primary_ip.server.ip_address} cat /etc/rancher/k3s/k3s.yaml | sed 's#127.0.0.1#${hcloud_primary_ip.server.ip_address}#' > ~/.kube/propuestas-prod.yaml && chmod 600 ~/.kube/propuestas-prod.yaml"
}
