variable "cluster_name" {
  description = "Prefijo de nombre para todos los recursos."
  type        = string
  default     = "propuestas"
}

variable "location" {
  description = "Ubicacion Hetzner. ash = Ashburn (US-East); nbg1/fsn1/hel1 = UE. Los tipos CX* solo existen en UE; en ash usar CPX*."
  type        = string
  default     = "ash"
}

variable "server_type_server" {
  description = "Tipo x86 del nodo k3s server (>= 8 GB RAM; corre Argo CD, observabilidad y CNPG)."
  type        = string
  default     = "cpx32" # 4 vCPU AMD / 8 GB. En UE: cx33 (mas barato).
}

variable "server_type_agent" {
  description = "Tipo x86 de los nodos agent (>= 4 GB RAM)."
  type        = string
  default     = "cpx22" # 2 vCPU AMD / 4 GB. En UE: cx23 (mas barato).
}

variable "agent_count" {
  description = "Numero de nodos agent (escalar = subir y tofu apply)."
  type        = number
  default     = 1
}

variable "ssh_public_key_path" {
  description = "Ruta a la llave publica SSH que se registra en Hetzner."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = "CIDRs con acceso a SSH (22) y API de Kubernetes (6443), p.ej. [\"203.0.113.7/32\"]. Obligatorio."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0") && !contains(var.admin_cidrs, "::/0")
    error_message = "admin_cidrs no puede estar vacio ni abrir 22/6443 al mundo."
  }
}

variable "k3s_version" {
  description = "Version de k3s; debe coincidir con clusters/local/k3d-config.yaml (rancher/k3s:v1.37.1-k3s1)."
  type        = string
  default     = "v1.37.1+k3s1"
}
