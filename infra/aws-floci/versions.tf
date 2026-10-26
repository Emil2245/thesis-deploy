terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
  }

  # Estado local (gitignored). En AWS real: backend "s3" + bloqueo con DynamoDB
  # (aquí sería circular: el bucket de estado viviría en el mismo emulador que se gestiona).
}

# Credenciales ficticias: el emulador no las valida; no son secretos.
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    acm            = var.floci_endpoint
    cloudwatch     = var.floci_endpoint
    cloudwatchlogs = var.floci_endpoint
    ec2            = var.floci_endpoint
    ecr            = var.floci_endpoint
    eks            = var.floci_endpoint
    elbv2          = var.floci_endpoint
    iam            = var.floci_endpoint
    kms            = var.floci_endpoint
    rds            = var.floci_endpoint
    route53        = var.floci_endpoint
    s3             = var.floci_endpoint
    secretsmanager = var.floci_endpoint
    sts            = var.floci_endpoint
  }
}
