output "hostname" {
  value       = var.db_host
  description = "RDS endpoint hostname"
}

output "port" {
  value       = var.db_port
  description = "RDS port"
}

output "master_secret_arn" {
  value       = var.master_secret_arn
  description = "ARN of the Secrets Manager secret for master credentials"
}

output "db_username" {
  value       = postgresql_role.app_user.name
  description = "Created database username"
}

output "db_password" {
  value       = random_password.user.result
  sensitive   = true
  description = "Database user password"
}

output "database_name" {
  value       = postgresql_database.app.name
  description = "Database name"
}
