output "rds_policy_arn" {
  description = "ARN of the RDS management policy"
  value       = local.iam_create ? aws_iam_policy.nullplatform_rds_policy[0].arn : ""
}

output "rds_sg_policy_arn" {
  description = "ARN of the EC2 security group policy"
  value       = local.iam_create ? aws_iam_policy.nullplatform_rds_sg_policy[0].arn : ""
}

output "rds_secretsmanager_policy_arn" {
  description = "ARN of the Secrets Manager policy"
  value       = local.iam_create ? aws_iam_policy.nullplatform_rds_secretsmanager_policy[0].arn : ""
}

output "permissions_role_arn" {
  description = "ARN of the rds-postgres-server permissions role assumed by the nullplatform agent role. Pass to the agent (assume_role_arns)."
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_server[0].arn : ""
}

output "permissions_role_name" {
  description = "Name of the rds-postgres-server permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_server[0].name : ""
}

output "permissions_role_id" {
  description = "ID of the rds-postgres-server permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_rds_postgres_server[0].id : ""
}
