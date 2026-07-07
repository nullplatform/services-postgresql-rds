terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "postgresql" {
  host      = var.db_host
  port      = var.db_port
  database  = "postgres"
  username  = var.master_username
  password  = var.master_password
  sslmode   = "require"
  superuser = false
}
