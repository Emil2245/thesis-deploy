variable "floci_endpoint" {
  type        = string
  description = "URL del emulador, p. ej. http://192.168.1.12:4566"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "access_key" {
  type    = string
  default = "test"
}

variable "secret_key" {
  type    = string
  default = "test"
}

variable "k8s_version" {
  type    = string
  default = "1.37"
}

variable "db_engine_version" {
  type    = string
  default = "18.4"
}

variable "alb_port" {
  type        = number
  default     = 8080
  description = "Puerto del listener HTTP del ALB (publicado por el compose de Floci)."
}

variable "nodeport_ingress" {
  type        = number
  default     = 30080
  description = "NodePort del Service de Traefik (k8s/platform/aws-floci/traefik)."
}

variable "alb_https_port" {
  type        = number
  default     = 8443
  description = "Puerto del listener HTTPS del ALB (publicado por el compose de Floci)."
}

variable "node_instance_type" {
  type    = string
  default = "m5.large"
}

variable "node_count" {
  type        = number
  default     = 2
  description = "Nodos de trabajo del grupo (G1). Floci solo materializa un nodo k3s por clúster; ver docs/evidencias/aws-floci-2026-10-v2.md."
}
