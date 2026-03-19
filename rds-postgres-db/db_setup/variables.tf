variable "service_id" {
  type        = string
  description = "Nullplatform service ID (used as keeper to stabilize password across re-applies)"
}

variable "db_host" {
  type        = string
  description = "RDS endpoint hostname"
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "RDS port"
}

variable "db_name" {
  type        = string
  description = "Database name to create"
}

variable "db_username" {
  type        = string
  description = "Username for the database user"
}

variable "master_username" {
  type        = string
  description = "Master username for connecting to PostgreSQL"
}

variable "master_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret for master credentials"
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master password for connecting to PostgreSQL (passed via auto.tfvars)"
}
