# rds-postgres-db

A nullplatform dependency service that provisions and manages a **PostgreSQL database** within an existing RDS instance managed by [`rds-postgres-server`](../rds-postgres-server). It handles database creation, app-level user management, and per-link fine-grained access control — without creating any AWS infrastructure itself.

## What It Does

- Auto-discovers a compatible `rds-postgres-server` in the same nullplatform namespace using dimension matching
- Creates a dedicated PostgreSQL database and application-level user within that server
- Manages per-link permissions: each link to an application gets its own PostgreSQL user with scoped grants (`read`, `write`, or `read-write`)
- Stores connection credentials in nullplatform service and link attributes for injection into applications

## Architecture

```
nullplatform Application
        │
        │ link (creates user + grants)
        ▼
 rds-postgres-db  ──────► rds-postgres-server  ──────► AWS RDS PostgreSQL
  (this service)           (auto-discovered)              │
        │                                                  ├─ database: app_<application_id>
        │                                                  ├─ user: app_<application_id>  (service-level)
        └─ per link:                                       └─ user: np_<link_id_prefix>   (per link)
             postgresql_role.<link>
             postgresql_grant.*
```

Unlike `rds-postgres-server`, this service creates no AWS resources. It only manages PostgreSQL-level objects (databases, roles, grants) on the shared RDS instance.

## Nullplatform Integration

- **Dependency service type**: registered as a `dependency` service in nullplatform
- **Auto-discovery**: at creation time, queries nullplatform for `dependency` services in the same namespace with `status=active` and attributes `hostname` + `master_secret_arn` set, filtered by matching dimensions
- **Service attributes**: writes connection metadata back to nullplatform via `np service patch`
- **Link attributes**: writes per-link credentials to nullplatform via `np link patch` for injection into application environment

### Service Attributes (written after create)

| Attribute | Visibility | Description |
|---|---|---|
| `hostname` | exported | RDS endpoint hostname |
| `port` | exported | RDS port (5432) |
| `username` | exported | Service-level PostgreSQL user |
| `password` | hidden | Service-level PostgreSQL password |
| `database_name` | exported | PostgreSQL database name |
| `master_secret_arn` | internal | Secrets Manager ARN (used for link operations) |

### Link Attributes (written per link)

| Attribute | Description |
|---|---|
| `username` | Per-link PostgreSQL user (`np_<first 16 chars of link_id>`) |
| `password` | Per-link PostgreSQL password |
| `database_name` | Database name (same as service-level database) |

## Link Parameters

| Parameter | Type | Required | Default | Allowed Values |
|---|---|---|---|---|
| `access_level` | enum | No | `read-write` | `read`, `write`, `read-write` |

### Access Level Grants

| Level | Grants |
|---|---|
| `read` | `CONNECT` on database, `USAGE` on schema, `SELECT` on tables and sequences |
| `write` | `CONNECT` on database, `USAGE` on schema, `INSERT`, `UPDATE`, `DELETE` on tables, `USAGE` on sequences |
| `read-write` | All of the above + `CREATE` on schema (allows running migrations) |

All access levels include `DEFAULT PRIVILEGES` so future tables created after the link also inherit the grants automatically.

## Workflows

| Workflow | Trigger | What It Does |
|---|---|---|
| `create` | Service created | Auto-discovers server, creates database + app user, writes service attributes |
| `update` | Service updated | No-op (no configurable parameters) |
| `delete` | Service deleted | Reassigns owned objects to master, destroys app user; **database is preserved** |
| `link` | Application linked | Creates per-link PostgreSQL user with scoped grants |
| `unlink` | Application unlinked | Revokes grants only; user and database are **preserved** |

## Database and Username Derivation

Database and username values are derived deterministically from nullplatform metadata:

**Service level** (one per service):
```
database_name = "app_<application_id>"
username      = "app_<application_id>"
```

**Link level** (one per link):
```
username = "np_<first 16 hex chars of link_id>"
# e.g., link_id = "a1b2c3d4-e5f6-..." → username = "np_a1b2c3d4e5f6..."
```

This ensures usernames are stable and reproducible even if the service is recreated.

## Requirements

### nullplatform Prerequisites

- An active **`rds-postgres-server`** service in the same nullplatform namespace with:
  - `status: active`
  - Matching dimensions (e.g., both services must have `cluster: prod`)
  - Attributes `hostname` and `master_secret_arn` already set (i.e., RDS instance successfully provisioned)
- The `rds-postgres-server` must expose a Secrets Manager secret with master PostgreSQL credentials

### AWS IAM Permissions

This service requires minimal AWS permissions compared to `rds-postgres-server`. The agent only needs:

- **Secrets Manager**: `GetSecretValue` — to retrieve the master PostgreSQL password from the ARN stored in service attributes

No RDS, EC2, or S3 permissions are needed.

### Runtime Dependencies

These tools are required inside the agent container:

- **OpenTofu 1.9.0** — auto-downloaded to `/tmp/np-tofu-bin/` if not available in `PATH`
- **AWS CLI** — for Secrets Manager queries
- **jq** — for JSON parsing
- **PostgreSQL client (`psql`)** — installed via `apk add postgresql-client`, used for the `reassign_owned` step during service deletion

## Important Considerations

### Auto-Discovery Behavior

At creation time, the service queries nullplatform for compatible `rds-postgres-server` instances. The discovery fails if:

- **0 servers found**: No active `rds-postgres-server` exists with matching dimensions in the namespace. Create one first.
- **More than 1 server found**: Multiple candidates match. The error output lists all matching servers. Add or adjust dimensions to make the match unambiguous.

### Database Is Never Destroyed

The PostgreSQL database has `lifecycle { prevent_destroy = true }` in Terraform. Even on service deletion, only the app-level user is destroyed — the database and all its data persist on the RDS instance. This is intentional to prevent accidental data loss.

To fully drop the database, connect directly to the RDS instance using the master credentials from Secrets Manager.

### Two-Phase Deletion

Service deletion runs in two steps:
1. **`reassign_owned`**: Transfers ownership of all database objects (tables, sequences, etc.) from the app user to the master user. This is required before dropping the app user, since PostgreSQL prevents dropping roles that own objects.
2. **`tofu destroy`** (targeted): Destroys only `postgresql_role.app_user` and `random_password.user`. The database is not touched.

### Stable Passwords

- The service-level password is stable for the lifetime of the service (keyed by `service_id`)
- Per-link passwords are stable across unlink/relink cycles (keyed by `link_id`)

Neither password changes unless the underlying Terraform resource is tainted or recreated.

### `read-write` Allows Schema Modifications

The `read-write` access level includes `CREATE` on the `public` schema. This is intentional to allow applications to run database migrations. If you need to prevent schema changes, use `read` or `write` instead.

### Dimension Alignment Is Critical

This service uses dimensions to match the correct `rds-postgres-server`. If dimensions are not aligned between the two services, discovery fails at creation time with a clear error. Ensure both services are created with the same dimension values.

### Service Must Exist Before Linking

If the service was created but the `hostname` attribute is empty (e.g., provisioning failed), link operations exit cleanly without performing any database changes. Ensure the service is fully created before attempting to link applications.
