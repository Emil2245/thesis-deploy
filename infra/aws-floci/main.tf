locals {
  tags = { project = "propuestas", env = "aws-floci", managed-by = "opentofu" }
}

# ---------------------------------------------------------------- red (metadatos en Floci)
resource "aws_vpc" "main" {
  cidr_block = "10.40.0.0/16"
  tags       = merge(local.tags, { Name = "propuestas" })
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.1.0/24"
  availability_zone = "${var.region}a"
  tags              = merge(local.tags, { Name = "propuestas-a" })
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.2.0/24"
  availability_zone = "${var.region}b"
  tags              = merge(local.tags, { Name = "propuestas-b" })
}

resource "aws_security_group" "cluster" {
  name        = "propuestas-cluster"
  description = "EKS propuestas"
  vpc_id      = aws_vpc.main.id
  tags        = local.tags
}

resource "aws_security_group" "alb" {
  name        = "propuestas-alb"
  description = "ALB HTTP"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = var.alb_port
    to_port     = var.alb_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}

# ---------------------------------------------------------------- KMS
resource "aws_kms_key" "main" {
  description             = "propuestas: cifrado de S3 y secretos"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/propuestas"
  target_key_id = aws_kms_key.main.key_id
}

# ---------------------------------------------------------------- IAM
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "propuestas-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "pods_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Rol de las cargas de propuestas (pod identity): leer sus secretos y escribir respaldos en S3.
resource "aws_iam_role" "workload" {
  name               = "propuestas-workload"
  assume_role_policy = data.aws_iam_policy_document.pods_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "workload" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.db.arn, aws_secretsmanager_secret.jwt.arn]
  }
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }
}

resource "aws_iam_policy" "workload" {
  name   = "propuestas-workload"
  policy = data.aws_iam_policy_document.workload.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "workload" {
  role       = aws_iam_role.workload.name
  policy_arn = aws_iam_policy.workload.arn
}

# ---------------------------------------------------------------- ECR
resource "aws_ecr_repository" "repo" {
  for_each             = toset(["propuestas-api", "propuestas-web"])
  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  force_delete = true
  tags         = local.tags
}

# ---------------------------------------------------------------- EKS
resource "aws_eks_cluster" "main" {
  name     = "propuestas"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids         = [aws_subnet.a.id, aws_subnet.b.id]
    security_group_ids = [aws_security_group.cluster.id]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags       = local.tags
  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "propuestas"
  service_account = "propuestas-workload"
  role_arn        = aws_iam_role.workload.arn
}

# ---------------------------------------------------------------- RDS
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "propuestas"
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
  tags       = local.tags
}

resource "aws_db_instance" "main" {
  identifier              = "propuestas-db"
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = "db.t3.small"
  allocated_storage       = 20
  db_name                 = "propuestas"
  username                = "propuestas"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.main.arn
  backup_retention_period = 7
  skip_final_snapshot     = true
  publicly_accessible     = false
  tags                    = local.tags
}

# ---------------------------------------------------------------- Secrets Manager
resource "aws_secretsmanager_secret" "db" {
  name                    = "propuestas/db"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}

resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "propuestas/jwt"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0
  tags                    = local.tags
}

# Mismo formato que scripts/seal-jwt.sh: PEM PKCS#8 privado + PEM SPKI público (RSA-2048).
resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    privateKey = tls_private_key.jwt.private_key_pem_pkcs8
    publicKey  = tls_private_key.jwt.public_key_pem
  })
}

# ---------------------------------------------------------------- S3
resource "aws_s3_bucket" "backups" {
  bucket        = "propuestas-backups"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# ---------------------------------------------------------------- CloudWatch
resource "aws_cloudwatch_log_group" "api" {
  name              = "/propuestas/api"
  retention_in_days = 14
  tags              = local.tags
}

# ---------------------------------------------------------------- credenciales de las cargas (sustituto de pod identity)
# Floci no inyecta credenciales de pod identity sin TLS (ver docs/evidencias/aws-floci-2026-10.md):
# el CronJob de respaldos y Fluent Bit usan la clave de este usuario IAM, con la MISMA política que el rol
# propuestas-workload. La clave de acceso la crea scripts/aws-floci/sync-secrets.sh (no vive en el estado).
resource "aws_iam_user" "workload" {
  name = "propuestas-workload"
  tags = local.tags
}

resource "aws_iam_user_policy_attachment" "workload" {
  user       = aws_iam_user.workload.name
  policy_arn = aws_iam_policy.workload.arn
}
