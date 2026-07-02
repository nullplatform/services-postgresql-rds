output "permissions_role_arn" {
  description = "ARN of the rds-postgres-db permissions role assumed by the nullplatform agent role. Pass to the agent (assume_role_arns)."
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_db[0].arn : ""
}

output "permissions_role_name" {
  description = "Name of the rds-postgres-db permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_db[0].name : ""
}

output "permissions_role_id" {
  description = "ID of the rds-postgres-db permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_db[0].id : ""
}

output "secretsmanager_policy_arn" {
  description = "ARN of the Secrets Manager read policy"
  value       = local.iam_create ? aws_iam_policy.nullplatform_rds_postgres_db_secretsmanager_policy[0].arn : ""
}
