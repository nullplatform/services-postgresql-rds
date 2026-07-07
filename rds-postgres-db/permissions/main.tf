# ---------------------------------------------------------------------------
# Permissions only — the database and user are created at service level
# (db_setup module). This module manages grants for a specific link.
# On unlink, only these grant resources are destroyed; the user and DB
# are preserved at service level.
# ---------------------------------------------------------------------------

resource "postgresql_grant" "connect" {
  database    = var.db_name
  role        = var.db_username
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "schema_usage" {
  database    = var.db_name
  role        = var.db_username
  schema      = "public"
  object_type = "schema"
  privileges  = local.schema_privileges[var.access_level]
}

# Grant on existing tables
resource "postgresql_grant" "tables" {
  database    = var.db_name
  role        = var.db_username
  schema      = "public"
  object_type = "table"
  privileges  = local.table_privileges[var.access_level]
}

# Grant on future tables (default privileges applied by master user)
resource "postgresql_default_privileges" "tables" {
  role        = var.db_username
  database    = var.db_name
  schema      = "public"
  owner       = var.master_username
  object_type = "table"
  privileges  = local.table_privileges[var.access_level]
}

# Grant USAGE on existing sequences (needed for INSERT on serial/bigserial columns)
resource "postgresql_grant" "sequences" {
  database    = var.db_name
  role        = var.db_username
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]
}

# Grant USAGE on future sequences
resource "postgresql_default_privileges" "sequences" {
  role        = var.db_username
  database    = var.db_name
  schema      = "public"
  owner       = var.master_username
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]
}
