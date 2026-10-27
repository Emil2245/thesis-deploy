# ---------------------------------------------------------------- ALB -> nodo EKS (NodePort)
# El cluster emulado es un único nodo k3s registrado como instancia EC2 por Floci.
# Los targets son de tipo ip (la IP del nodo): Floci no resuelve el id de instancia de los nodos EKS
# (Instance.containerBridgeIp vacío -> "Refusing to proxy to target i-..."); en AWS real sería target_type = "instance".
data "aws_instances" "nodes" {
  instance_state_names = ["running"]
  filter {
    name   = "tag:eks:cluster-name"
    values = [aws_eks_cluster.main.name]
  }
}

locals {
  public_ip = regex("//([^:/]+)", var.floci_endpoint)[0]
}

resource "aws_lb" "main" {
  name               = "propuestas"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]
  security_groups    = [aws_security_group.alb.id]
  tags               = local.tags
}

# Un solo target group: el NodePort de Traefik (G5) en TODOS los nodos. Los nodos adicionales (add-workers.sh) tienen IP fija
# 172.18.0.20x en la red docker de Floci.
resource "aws_lb_target_group" "ingress" {
  name        = "propuestas-ingress"
  protocol    = "HTTP"
  port        = var.nodeport_ingress
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path    = "/"
    matcher = "200"
  }
  tags = local.tags
}

resource "aws_lb_target_group_attachment" "ingress" {
  count             = var.node_count
  target_group_arn  = aws_lb_target_group.ingress.arn
  target_id         = count.index == 0 ? data.aws_instances.nodes.private_ips[0] : "172.18.0.${200 + count.index}"
  availability_zone = "all"
  port              = var.nodeport_ingress
}

# HTTPS (G6): certificado importado en ACM (CA propia generada abajo). HTTP solo redirige.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.alb_https_port
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.main.arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress.arn
  }
}

# HTTP: redirige a HTTPS cuando el emulador termina TLS (var.alb_redirect_http); si no, reenvía (ver variables.tf).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.alb_port
  protocol          = "HTTP"
  default_action {
    type             = var.alb_redirect_http ? "redirect" : "forward"
    target_group_arn = var.alb_redirect_http ? null : aws_lb_target_group.ingress.arn
    dynamic "redirect" {
      for_each = var.alb_redirect_http ? [1] : []
      content {
        port        = tostring(var.alb_https_port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# ---------------------------------------------------------------- ACM + Route53 (emulados)
# CA propia + certificado de servidor para el ALB (SAN: IP de la VM, nombre interno y localhost). El navegador solo confía
# tras importar la CA (output alb_ca_pem). En AWS real: certificado público de ACM validado por DNS.
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 8760
  allowed_uses          = ["cert_signing", "crl_signing"]
  subject {
    common_name  = "Propuestas aws-floci CA"
    organization = "propuestas"
  }
}

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem
  dns_names       = ["app.propuestas.aws.internal", "localhost"]
  ip_addresses    = [local.public_ip]
  subject {
    common_name = "app.propuestas.aws.internal"
  }
}

resource "tls_locally_signed_cert" "alb" {
  cert_request_pem      = tls_cert_request.alb.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "aws_acm_certificate" "main" {
  private_key       = tls_private_key.alb.private_key_pem
  certificate_body  = tls_locally_signed_cert.alb.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
  tags              = local.tags
}

resource "aws_route53_zone" "internal" {
  name = "propuestas.aws.internal"
  vpc {
    vpc_id = aws_vpc.main.id
  }
  tags = local.tags
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "app.propuestas.aws.internal"
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
