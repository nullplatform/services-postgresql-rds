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
- For AssumeRole to work (not just fail open to agent credentials — see below): an **`aws-iam-configuration`** provider (from `tofu-modules//nullplatform/identity-access-control`) registered at the **namespace-level NRN**. Unlike `rds-postgres-server`, this service does not need `aws-configuration`/`aws-networking-configuration` providers — `build_context` reads `region` from `values.yaml` (default `us-east-1`), not from a nullplatform provider.

### AWS IAM Permissions

This service requires minimal AWS permissions compared to `rds-postgres-server`. The agent needs:

- **Secrets Manager**: `GetSecretValue` — to retrieve the master PostgreSQL password from the ARN stored in service attributes
- **S3**: full lifecycle on the `np-service-<SERVICE_ID>` bucket — `build_context` creates and manages its own per-service Terraform state bucket, same as `rds-postgres-server`

No RDS or EC2 permissions are needed.

The `requirements/` Terraform module creates a dedicated IAM role
(`nullplatform-<cluster_name>-rds-postgres-db-role`) holding these policies,
with a trust policy allowing the nullplatform agent role to `sts:AssumeRole`
on it. Pass `cluster_name` (required) and optionally `agent_role_arn`
(defaults to `nullplatform-<cluster_name>-agent-role`) when applying it.
Granting the agent itself permission to assume this role is handled
separately, outside this module.

This role and its policy are shared per **cluster**, not per linked
`rds-postgres-server` instance — the `GetSecretValue` grant is scoped to the
`nullplatform/rds/*` secret-name prefix (every master secret in the cluster
following that naming convention), not to the single secret this particular
service instance's link actually uses. Anything that assumes this role can
read the master password of any `rds-postgres-server` in the cluster, not
just the linked one.

### AssumeRole Setup Guide

Three separate pieces must all be in place for the agent to actually assume
`nullplatform-<cluster_name>-rds-postgres-db-role` at runtime — applying
`requirements/` alone is not enough:

1. **Apply `requirements/`** with `cluster_name` (and optionally
   `agent_role_arn`) — creates the role and its trust policy (see above).
2. **Grant the agent permission to assume it.** Not managed by
   `requirements/` — add an inline (or managed) policy to the **agent's own**
   IAM role:
   ```json
   {
     "Effect": "Allow",
     "Action": "sts:AssumeRole",
     "Resource": "arn:aws:iam::<account-id>:role/nullplatform-<cluster_name>-rds-postgres-db-role"
   }
   ```
3. **Register the role as an `identity-access-control` provider** in
   nullplatform, at the **namespace-level NRN**
   (`organization=...:account=...:namespace=...` — without `:application=...`),
   with selector `rds-postgres-db`:
   ```hcl
   module "identity_access_control" {
     source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/identity-access-control?ref=<tag>"
     nrn    = "organization=<org>:account=<account>:namespace=<namespace>"
     attributes = {
       iam_role_arns = {
         arns = [{ selector = "rds-postgres-db", arn = "<role ARN from step 1>" }]
       }
     }
   }
   ```

`scripts/aws/assume_role_step` resolves the role by querying
`np provider list` / `np provider read` for this provider at the service's
**namespace NRN** — not by reading `CONTEXT.providers[...]`. This was
confirmed live: this platform's agent never populates `CONTEXT.providers`
regardless of the `provider_categories` declared in `values.yaml` or the
workflow YAMLs, so the lookup goes through the `np` CLI directly instead.

**If any of the 3 steps is missing**, `assume_role_step` logs
`assume_role=skipped (using agent credentials)` and the workflow proceeds
under the **agent's own role** — which fails with `AccessDenied` on S3/
Secrets Manager calls unless the agent happens to have those permissions
directly attached. This fail-open behavior is intentional (mirrors
`nullplatform/scopes-static-files`), but it means a misconfigured
AssumeRole setup fails *silently* as what looks like a permissions problem
rather than a missing-provider problem — check the `assume role` step's
log line first when debugging `AccessDenied` errors from later steps.

### Auto-Discovery NRN Requirement

`scripts/aws/build_db_setup_context` looks up the active `rds-postgres-server`
via `np service list --nrn <entity_nrn>`, using the service's **full
`entity_nrn` as-is** (including the `:application=...` segment) — not a
namespace-level NRN with that segment stripped. Confirmed live: querying
`np service list` at the namespace level (`:application=...` removed)
returns **zero results**, even when a healthy, matching `rds-postgres-server`
exists — `np service list --nrn` requires the exact NRN a service is scoped
at, it does not search hierarchically down from a broader NRN. If you see
`ERROR: No active RDS server found in <nrn> matching dimensions: ...` and
you're certain a matching, active server exists, check that this NRN is
being derived correctly rather than assuming the server itself is
misconfigured.

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

### Orphaned PostgreSQL Roles From Failed Creates

The service-level username/database name are derived from `application_id`
(`app_<application_id>`), which is the **same across every retry** of
creating this service for a given application — unlike `service_id`, which
is different each time. If a `create` action fails *after*
`postgresql_role.app_user` is created in Postgres but *before* the
workflow reaches `write service outputs` (so the service's `hostname`
attribute never gets set), a later `delete` action can't clean it up: it
checks the stored `hostname` attribute first, finds it empty, and skips
DB cleanup entirely (see "Service Must Exist Before Linking" above) —
leaving the Postgres role behind. The next `create` retry then fails with
`role "app_<application_id>" already exists`, even though nullplatform has
no record of a working service. If you hit this, connect to the RDS
instance with master credentials and run
`DROP ROLE IF EXISTS app_<application_id>;` (after reassigning/dropping any
objects it owns, if it had time to create any) before retrying.
