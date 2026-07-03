################################################################################
# Permissions role — assumed by the nullplatform agent role (sts:AssumeRole)
################################################################################

resource "aws_iam_role" "nullplatform_rds_postgres_db" {
  count = local.iam_create ? 1 : 0

  name        = local.role_name
  description = "Permissions role assumed by the nullplatform agent role for rds-postgres-db in cluster ${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = concat([local.agent_role_arn], var.additional_agent_role_arns) }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.iam_default_tags
}

################################################################################
# Secrets Manager IAM policy — read-only access to the RDS master password
################################################################################

resource "aws_iam_policy" "nullplatform_rds_postgres_db_secretsmanager_policy" {
  count = local.iam_create ? 1 : 0

  name        = "nullplatform-${var.cluster_name}-rds-postgres-db-secretsmanager-policy"
  description = "Policy for reading the RDS master password from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:nullplatform/rds/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_postgres_db_secretsmanager" {
  count      = local.iam_create ? 1 : 0
  role       = aws_iam_role.nullplatform_rds_postgres_db[0].name
  policy_arn = aws_iam_policy.nullplatform_rds_postgres_db_secretsmanager_policy[0].arn
}

################################################################################
# S3 IAM policy (per-service tfstate buckets: np-service-<id>)
################################################################################

# Grant permissions to manage the per-link S3 bucket used to store tofu state.
# build_context creates its own np-service-<SERVICE_ID> bucket, same as
# rds-postgres-server — confirmed missing via a live test (AccessDenied on
# s3:CreateBucket while assuming this role).
resource "aws_iam_policy" "nullplatform_rds_postgres_db_s3_policy" {
  count = local.iam_create ? 1 : 0

  name        = "nullplatform-${var.cluster_name}-rds-postgres-db-s3-policy"
  description = "Policy for managing per-service S3 tfstate buckets (np-service-*)"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:HeadBucket",
          "s3:PutBucketVersioning",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:DeleteBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::np-service-*",
          "arn:aws:s3:::np-service-*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_postgres_db_s3" {
  count      = local.iam_create ? 1 : 0
  role       = aws_iam_role.nullplatform_rds_postgres_db[0].name
  policy_arn = aws_iam_policy.nullplatform_rds_postgres_db_s3_policy[0].arn
}
