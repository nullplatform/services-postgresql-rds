# ---------------------------------------------------------------------------
# Database — created on service create, preserved on service delete.
#
# On re-creates (database already exists), do_tofu runs
# "tofu import postgresql_database.app <db_name>" before apply so no data
# is lost. prevent_destroy ensures tofu destroy never drops the DB.
# ---------------------------------------------------------------------------

resource "postgresql_database" "app" {
  name  = var.db_name
  owner = var.master_username

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# App user — password is stable for the lifetime of the service.
# keepers use service_id so the password only regenerates if the service
# itself is recreated with a different ID.
# ---------------------------------------------------------------------------

resource "random_password" "user" {
  length  = 32
  special = false
  keepers = {
    service_id = var.service_id
  }
}

resource "postgresql_role" "app_user" {
  name     = var.db_username
  password = random_password.user.result
  login    = true
}

# ---------------------------------------------------------------------------
# App credentials, mirrored into Secrets Manager (same convention as the
# rds-postgres-server master secret) so they're not only reachable via
# nullplatform service/link attributes.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name                    = "nullplatform/rds/${var.service_id}/app"
  recovery_window_in_days = 0

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    username = postgresql_role.app_user.name
    password = random_password.user.result
    host     = var.db_host
    port     = var.db_port
    dbname   = postgresql_database.app.name
  })
}
