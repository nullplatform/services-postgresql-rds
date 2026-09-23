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
# Secrets Manager IAM policy — read the RDS master password, manage the
# app-level credentials secret this service creates in db_setup/
################################################################################

resource "aws_iam_policy" "nullplatform_rds_postgres_db_secretsmanager_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}-rds-postgres-db-secretsmanager-policy"
  description = "Policy for reading the RDS master password and managing the app-level credentials secret in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:TagResource",
        "secretsmanager:UntagResource",
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:ListSecretVersionIds"
      ]
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
# S3 IAM policy (the state bucket the operator names)
################################################################################

# Read/write access to the state bucket the operator names, and to nothing else.
resource "aws_iam_policy" "nullplatform_rds_postgres_db_s3_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}-rds-postgres-db-s3-policy"
  description = "Access to the S3 bucket holding the tofu state for this service"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : local.shared_state_statements
  })
}

resource "aws_iam_role_policy_attachment" "rds_postgres_db_s3" {
  count      = local.iam_create ? 1 : 0
  role       = aws_iam_role.nullplatform_rds_postgres_db[0].name
  policy_arn = aws_iam_policy.nullplatform_rds_postgres_db_s3_policy[0].arn
}
