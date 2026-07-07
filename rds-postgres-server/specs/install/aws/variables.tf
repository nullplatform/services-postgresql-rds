variable "nrn" {
  description = "NullPlatform Resource Name (namespace-level, e.g. organization=<org>:account=<account>:namespace=<namespace>) where the service definition is registered."
  type        = string
}

variable "np_api_key" {
  description = "nullplatform API key used by the agent association to authenticate against the nullplatform API."
  type        = string
  sensitive   = true
}

variable "tags_selectors" {
  description = "Agent tag selectors for the notification channel (must match the tags the target agent registers with)."
  type        = map(string)
}

variable "service_name" {
  description = "Display name for the rds-postgres-server service in nullplatform."
  type        = string
  default     = "RDS Postgres Server"
}

variable "repository_org" {
  description = "GitHub organization owning the services repository."
  type        = string
  default     = "nullplatform"
}

variable "repository_name" {
  description = "Repository name containing the rds-postgres-server service spec templates."
  type        = string
  default     = "services-postgresql-rds"
}

variable "repository_branch" {
  description = "Branch of the services repository to register the service spec/links/entrypoint from."
  type        = string
  default     = "main"
}

variable "repository_token" {
  description = "Access token for private repositories. Unnecessary for a public repository."
  type        = string
  default     = null
  sensitive   = true
}

# --- account-level providers (account.region + vpc.id) -----------------------

variable "create_account_providers" {
  description = "Whether to register the aws-configuration/aws-networking-configuration providers at the account-level NRN. Set to false if another stack in this account already registers them (they are shared account-wide, not specific to rds-postgres-server)."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for the aws-configuration provider. Required when create_account_providers is true."
  type        = string
  default     = ""
}

variable "hosted_private_zone_id" {
  description = "Private Route53 hosted zone ID for the aws-configuration provider. Required when create_account_providers is true."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for the aws-networking-configuration provider. Required when create_account_providers is true."
  type        = string
  default     = ""
}

variable "vpc_subnets" {
  description = "Subnet IDs for the aws-networking-configuration provider. Pass whatever the cluster's VPC provider already uses for other scopes/services — this service only reads vpc.id from it, not this list. Required when create_account_providers is true."
  type        = list(string)
  default     = []
}

variable "vpc_security_groups" {
  description = "Security group IDs for the aws-networking-configuration provider (e.g. the node/cluster security group). Required when create_account_providers is true."
  type        = list(string)
  default     = []
}

# --- account-level provider (AssumeRole target) -------------------------------

variable "create_identity_access_control" {
  description = "Whether to register the aws-iam-configuration provider at the account-level NRN (derived from var.nrn). This is the only place that should create it for the account — see the comment in main.tf. Set to false if it is already managed elsewhere."
  type        = bool
  default     = true
}

variable "rds_postgres_server_role_arn" {
  description = "ARN of the rds-postgres-server permissions role (the permissions_role_arn output of ../../requirements/aws). Required when create_identity_access_control is true."
  type        = string
  default     = ""
}

variable "rds_postgres_db_role_arn" {
  description = "ARN of the rds-postgres-db permissions role (the permissions_role_arn output of the rds-postgres-db requirements/aws module), if that service is also installed in this account. When set, its selector is folded into this same aws-iam-configuration provider instead of rds-postgres-db registering its own — see the comment in main.tf for why."
  type        = string
  default     = ""
}
