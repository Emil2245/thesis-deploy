# ---------------------------------------------------------------- ALB -> nodo EKS (NodePort)
# El cluster emulado es un único nodo k3s registrado como instancia EC2 por Floci.
data "aws_instances" "nodes" {
  instance_state_names = ["running"]
  filter {
    name   = "tag:eks:cluster-name"
    values = [aws_eks_cluster.main.name]
  }
}

resource "aws_lb" "main" {
  name               = "propuestas"
  load_balancer_type = "application"
  internal           = false
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]
  security_groups    = [aws_security_group.alb.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "web" {
  name        = "propuestas-web"
  protocol    = "HTTP"
  port        = var.nodeport_web
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path    = "/"
    matcher = "200"
  }
  tags = local.tags
}

resource "aws_lb_target_group" "api" {
  name        = "propuestas-api"
  protocol    = "HTTP"
  port        = var.nodeport_api
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path    = "/api/v1/config/display"
    matcher = "200"
  }
  tags = local.tags
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = data.aws_instances.nodes.ids[0]
  port             = var.nodeport_web
}

resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = data.aws_instances.nodes.ids[0]
  port             = var.nodeport_api
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.alb_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ---------------------------------------------------------------- ACM + Route53 (emulados)
resource "aws_acm_certificate" "main" {
  domain_name       = "propuestas.aws.internal"
  validation_method = "DNS"
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
