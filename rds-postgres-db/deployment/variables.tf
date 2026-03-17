variable "service_id" {
  type        = string
  description = "Nullplatform service ID"
}

variable "instance_name" {
  type        = string
  description = "Unique instance name for AWS resource naming (format: np-<service_id>)"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the RDS instance will be deployed"
}

variable "instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "RDS instance class"
}

variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Allocated storage in GB"
}

variable "postgres_version" {
  type        = string
  default     = "16"
  description = "PostgreSQL major version"
}

variable "multi_az" {
  type        = bool
  default     = false
  description = "Enable Multi-AZ deployment for high availability"
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated backups. 0 disables backups."
}

variable "backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily time range for automated backups (UTC, hh:mm-hh:mm)"
}

variable "maintenance_window" {
  type        = string
  default     = "Mon:04:00-Mon:05:00"
  description = "Weekly time range for maintenance operations (UTC, ddd:hh:mm-ddd:hh:mm)"
}
