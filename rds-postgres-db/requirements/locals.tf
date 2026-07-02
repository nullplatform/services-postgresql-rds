locals {
  iam_module_name = "requirements-rds-postgres-db"
  iam_create      = var.iam_create_role

  role_name      = var.role_name != "" ? var.role_name : "nullplatform-${var.cluster_name}-rds-postgres-db-role"
  agent_role_arn = var.agent_role_arn != "" ? var.agent_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nullplatform-${var.cluster_name}-agent-role"

  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "rds-postgres-db"
    Module    = local.iam_module_name
  })
}
