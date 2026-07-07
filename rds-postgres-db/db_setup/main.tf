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
