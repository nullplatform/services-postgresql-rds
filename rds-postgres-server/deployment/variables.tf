variable "service_id" {
  type        = string
  description = "Nullplatform service ID"
}

variable "instance_name" {
  type        = string
  description = "Unique instance name for AWS resource naming (format: <service_slug>-<service_id>, at most 63 characters; existing instances keep the name in their state)"
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

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the DB subnet group, from vpc.subnets of the vpc provider"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids needs at least two subnets in different availability zones"
  }
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

variable "secret_kms_key_id" {
  type        = string
  default     = null
  description = "KMS key ID or ARN used to encrypt the RDS master secret in Secrets Manager. If not set, AWS encrypts it with the default aws/secretsmanager managed key."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of an existing KMS key for RDS storage encryption. When null, the module creates a dedicated key."
}
