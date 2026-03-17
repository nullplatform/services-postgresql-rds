variable "link_id" {
  type        = string
  description = "Nullplatform link ID (used as keeper to stabilize password across re-applies)"
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
  description = "Database name to create inside the RDS instance"
}

variable "db_username" {
  type        = string
  description = "Username for the new database user (derived from link ID)"
}

variable "master_username" {
  type        = string
  description = "Master username for connecting to PostgreSQL"
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master password for connecting to PostgreSQL (passed via auto.tfvars)"
}

variable "access_level" {
  type        = string
  default     = "read-write"
  description = "Permission level: read, write, or read-write"

  validation {
    condition     = contains(["read", "write", "read-write"], var.access_level)
    error_message = "access_level must be one of: read, write, read-write"
  }
}
