output "hostname" {
  value       = aws_db_instance.main.address
  description = "RDS endpoint hostname"
}

output "port" {
  value       = aws_db_instance.main.port
  description = "RDS port"
}

output "db_instance_identifier" {
  value       = aws_db_instance.main.identifier
  description = "AWS RDS instance identifier"
}

output "master_secret_arn" {
  value       = aws_secretsmanager_secret.master.arn
  description = "ARN of the Secrets Manager secret for master credentials"
}
