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
