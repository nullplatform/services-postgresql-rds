locals {
  table_privileges = {
    # read: SELECT only
    "read" = ["SELECT"]

    # write: INSERT/UPDATE/DELETE without SELECT (write-only)
    "write" = ["INSERT", "UPDATE", "DELETE"]

    # read-write: full DML access
    "read-write" = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  }
}
