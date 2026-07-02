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

  name        = "nullplatform-${var.cluster_name}-rds-secretsmanager-policy"
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
