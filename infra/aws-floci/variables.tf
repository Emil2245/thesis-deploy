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

variable "nodeport_web" {
  type    = number
  default = 30080
}

variable "nodeport_api" {
  type    = number
  default = 30081
}
