output "eks_cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "eks_cluster_name" { value = aws_eks_cluster.main.name }
output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_listener_port" { value = var.alb_port }
output "rds_endpoint" { value = aws_db_instance.main.endpoint }
output "ecr_repository_urls" { value = { for k, r in aws_ecr_repository.repo : k => r.repository_url } }
output "secret_arns" {
  value = { db = aws_secretsmanager_secret.db.arn, jwt = aws_secretsmanager_secret.jwt.arn }
}
output "backups_bucket" { value = aws_s3_bucket.backups.bucket }
output "kms_key_alias" { value = aws_kms_alias.main.name }
output "pod_role_arns" { value = { for k, r in aws_iam_role.pod : k => r.arn } }
output "log_group" { value = aws_cloudwatch_log_group.api.name }
output "alb_https_port" { value = var.alb_https_port }
output "alb_ca_pem" { value = tls_self_signed_cert.ca.cert_pem }
output "alb_redirect_http" { value = var.alb_redirect_http }
