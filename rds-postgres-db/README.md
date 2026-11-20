# rds-postgres-db

A nullplatform dependency service that provisions and manages a **PostgreSQL database** within an existing RDS instance managed by [`rds-postgres-server`](../rds-postgres-server). It handles database creation, app-level user management, and per-link fine-grained access control. Unlike `rds-postgres-server`, it does not provision any RDS/EC2 infrastructure — the one AWS resource it does create is the Secrets Manager secret holding the app-level PostgreSQL credentials.

## What It Does

- Auto-discovers a compatible `rds-postgres-server` in the same nullplatform namespace using dimension matching
- Creates a dedicated PostgreSQL database and application-level user within that server
- Manages per-link permissions: each link to an application gets its own PostgreSQL user with scoped grants (`read`, `write`, or `read-write`)
- Stores connection credentials in nullplatform service and link attributes for injection into applications, and mirrors the app-level credentials into a Secrets Manager secret (same convention as the `rds-postgres-server` master secret)

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

Unlike `rds-postgres-server`, this service creates no RDS/EC2 infrastructure — it only manages PostgreSQL-level objects (databases, roles, grants) on the shared RDS instance, plus one Secrets Manager secret for the app-level credentials it generates.

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
| `master_secret_arn` | internal | Secrets Manager ARN for the `rds-postgres-server` master credentials (used for link operations) |
| `app_secret_arn` | internal | Secrets Manager ARN for this service's own app-level credentials |

### Link Attributes (written per link)

| Attribute | Description |
|---|---|
| `username` | Per-link PostgreSQL user (`np_<first 16 chars of link_id>`) |
| `password` | Per-link PostgreSQL password |
| `database_name` | Database name (same as service-level database) |
| `app_secret_arn` | Secrets Manager ARN for the service-level app credentials (mirrored from the service attribute) |

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
| `create` | Service created | Auto-discovers server, creates database + app user, stores app credentials in Secrets Manager, writes service attributes |
| `update` | Service updated | No-op (no configurable parameters) |
| `delete` | Service deleted | Reassigns owned objects to master, destroys app user and its Secrets Manager secret; **database is preserved** |
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

## Infrastructure Resources Created

| Resource | Description |
|---|---|
| `postgresql_database` | The application database (preserved on delete) |
| `postgresql_role` | The service-level app user |
| `aws_secretsmanager_secret` | Stores the app-level credentials (`nullplatform/rds/<service_id>/app`); destroyed alongside the app user on service delete |

No RDS, EC2, or VPC resources are created — those belong to the auto-discovered `rds-postgres-server`.

## Requirements

### nullplatform Prerequisites

- The package installed in the organization, with its agent channel — see
  [Install in your organization](#install-in-your-organization) below.
- An active **`rds-postgres-server`** service in the same nullplatform namespace with:
  - `status: active`
  - Matching dimensions (e.g., both services must have `cluster: prod`)
  - Attributes `hostname` and `master_secret_arn` already set (i.e., RDS instance successfully provisioned)
- The `rds-postgres-server` must expose a Secrets Manager secret with master PostgreSQL credentials
- For AssumeRole to work (not just fail open to agent credentials — see below): an **`aws-iam-configuration`** provider (from `tofu-modules//nullplatform/identity-access-control`) registered at the **account-level NRN** (or any ascendant of the service's NRN — resolution walks up the hierarchy). Unlike `rds-postgres-server`, this service does not need `aws-configuration`/`aws-networking-configuration` providers — `build_context` reads `region` from `values.yaml` (default `us-east-1`), not from a nullplatform provider.

### AWS IAM Permissions

This service requires fewer AWS permissions than `rds-postgres-server` (no RDS/EC2), but it does manage its own Secrets Manager secret. The agent needs:

- **Secrets Manager**: `GetSecretValue` — to retrieve the master PostgreSQL password from the ARN stored in service attributes; plus `CreateSecret`, `PutSecretValue`, `UpdateSecret`, `DeleteSecret`, `DescribeSecret`, `TagResource`, `UntagResource`, `GetResourcePolicy`, `ListSecretVersionIds` — to create, update, and delete the app-level credentials secret this service owns
- **S3**: read/write on the state bucket named by `state_bucket_name`, and nothing else

Set `RDS_POSTGRES_S3_STATE_BUCKET` on the agent to the name of an existing S3 bucket and every service instance keeps its Terraform state there under `services/rds-postgres/<service-id>/`. Both packages share the bucket; the service id keeps their keys apart. Deleting a service removes only its own prefix and never touches the bucket.

The bucket must already exist — the service does not create it, and any name works. Pass it as `state_bucket_name` to the `specs/requirements/aws` module, which grants the role access to that bucket and nothing else.

`RDS_POSTGRES_S3_STATE_BUCKET` is required. Without it every action fails before touching AWS.

Earlier versions created one bucket per instance (`np-service-<service-id>`) and deleted it with the service. That is gone. **Instances provisioned by those versions must have their state moved before the next action runs**, or tofu will start from an empty state and try to create infrastructure that already exists:

```bash
aws s3 cp --recursive "s3://np-service-<service-id>/" \
                      "s3://<shared-bucket>/services/rds-postgres/<service-id>/"
aws s3 rb "s3://np-service-<service-id>" --force
```

The old bucket can go once the copy is verified.

No RDS or EC2 permissions are needed.

The `requirements/` Terraform module creates a dedicated IAM role
(`nullplatform-<cluster_name>-rds-postgres-db-role`) holding these policies,
with a trust policy allowing the nullplatform agent role to `sts:AssumeRole`
on it. Pass `cluster_name` (required) and optionally `agent_role_arn`
(defaults to `nullplatform-<cluster_name>-agent-role`), `role_name` (defaults
to `nullplatform-<cluster_name>-rds-postgres-db-role`) and
`policies_name_prefix` (defaults to `nullplatform-<cluster_name>`) when
applying it. Granting the agent itself permission to assume this role is
handled separately, outside this module.

This role and its policy are shared per **cluster**, not per linked
`rds-postgres-server` instance — the Secrets Manager grant is scoped to the
`nullplatform/rds/*` secret-name prefix (every master and app secret in the
cluster following that naming convention), not to the single secrets this
particular service instance actually owns. Anything that assumes this role
can read, create, update, or delete any secret under that prefix — not just
the master password of the linked server, and not just this instance's own
app secret. This is a wider blast radius than a read-only grant would be;
narrowing it to per-instance secret ARNs would require generating the policy
per service instance instead of once per cluster.

### Install in your organization

The service is published once as the package `np-rds-postgres-db` (specification "RDS PostgreSQL DB"), visible to every organization. You do not copy its specs: you install the package and use it read-only. How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this service.

Already registered a copy from the former `specs/install`? It keeps working: it called tofu-modules' `service_definition` on specs that stay in every release, and the package installs next to it, as the guide explains. If you sourced that directory as a module, pin its `?ref` to a release that still has it.

Installing it touches the same three layers as registering a service yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (AWS credentials) | The IAM role the service assumes, with access to the state bucket | [`specs/requirements/aws`](specs/requirements/aws) |
| nullplatform (nullplatform API key) | The installation of the package and the agent channel | tofu-modules' `service_package_installation` |
| bindings | The role under selector `rds-postgres-db` in your IAM provider | your `aws-iam-configuration` provider |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/services-postgresql-rds/releases)) and use its version in both places below: the IAM role is the one the worker of that same release expects. Both services of this repository share the release, so install them at the same version.

```hcl
# ── infrastructure layer ─────────────────────────────────────────────
module "rds_postgres_db_requirements" {
  source            = "git::https://github.com/nullplatform/services-postgresql-rds.git//rds-postgres-db/specs/requirements/aws?ref=vX.Y.Z"
  cluster_name      = "<nullplatform agent cluster>"
  state_bucket_name = "<existing S3 bucket for the tofu state>"
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.rds_postgres_db_requirements.permissions_role_arn]

# ── nullplatform layer ───────────────────────────────────────────────
# For a service the installation is the whole nullplatform side, channel included.
module "rds_postgres_db" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_package_installation?ref=v9.16.0"

  nrn                  = var.nrn
  package_slug         = "np-rds-postgres-db"
  package_version      = "X.Y.Z" # the same release, without the v
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}
# Keeping channels in a separate bindings layer instead? Use
# nullplatform/package_installation here and service_definition_agent_association
# there, with package_slug = "np-rds-postgres-db".

# ── bindings layer ───────────────────────────────────────────────────
# One aws-iam-configuration per NRN and dimensions, at the account level: add
# the entry to the list your IAM provider already has. Both services of this
# repository go in the SAME provider, one selector each.
#   { selector = "rds-postgres-db", arn = module.rds_postgres_db_requirements.permissions_role_arn }
```

**The state bucket.** Set `RDS_POSTGRES_S3_STATE_BUCKET` on the worker (a per-package env patch in tofu-modules' `nullplatform/agent`) to the name of an existing S3 bucket, and pass the same name to the requirements module as `state_bucket_name`. Every instance keeps its Terraform state there under `services/rds-postgres/<service-id>/`; both services share the bucket and the service id keeps their keys apart. The bucket must already exist: the service never creates or deletes it, and without the variable every action fails before touching AWS.

The service assumes the role it finds under selector `rds-postgres-db` in the IAM provider closest to its NRN. To upgrade, move the release in both layers: `ref` of the requirements module and `package_version` of the installation. See tofu-modules' [`service_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/service_package_installation) for its inputs and outputs.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries` and `np-rds-postgres-db` in its `worker_orchestrated_packages` (the worker then runs with the agent's identity, the one the role trusts); it needs no `aws-configuration` nor `aws-networking-configuration` provider, `build_context` reads `region` from `values.yaml`.

`scripts/aws/assume_role_step` resolves the role by querying
`np provider list --categories identity-access-control` with the service's
**full NRN as-is** (not stripped) — not by reading `CONTEXT.providers[...]`.
`--categories` resolves up the NRN hierarchy, so it finds the provider
registered at the account level above regardless of how deep the service's
own NRN is. This was confirmed live: an earlier version of this script
stripped the NRN to namespace level and did a plain `np provider list`
filtered by `stored_keys`, which does **not** inherit providers from
ascendant NRN levels — the account-level provider was never found and the
step silently fell back to agent credentials. Separately, `CONTEXT.providers[...]`
itself was also confirmed live to never populate on this platform version
regardless of the `provider_categories` declared in `values.yaml` or the
workflow YAMLs, so the lookup goes through the `np` CLI directly either way.

The lookup also passes `--dimensions` (derived from `.service.dimensions` in
`CONTEXT`, e.g. `cluster:prod`) so that if more than one
`identity-access-control` provider is ever registered at the same NRN
for different dimensions, `np` resolves the most-specific match instead
of an arbitrary one being picked client-side. Today the setup above
registers a single, dimension-less provider per account, so this is a
no-op — it only matters if per-dimension AssumeRole roles are introduced
later.

**If any of the 3 steps is missing**, `assume_role_step` logs
`assume_role=skipped (using agent credentials)` and the workflow proceeds
under the **agent's own role** — which fails with `AccessDenied` on S3/
Secrets Manager calls unless the agent happens to have those permissions
directly attached. This fail-open behavior is intentional (mirrors
`nullplatform/scopes-static-files`), but it means a misconfigured
AssumeRole setup fails *silently* as what looks like a permissions problem
rather than a missing-provider problem — check the `assume role` step's
log line first when debugging `AccessDenied` errors from later steps.

### How the package is published

Every release publishes a new revision of the package from this repository, in the same run that pushes the worker image ([`.github/workflows/release.yml`](../.github/workflows/release.yml)): the `publish-package` job applies [`rds-postgres-db/publish`](publish), a stack on tofu-modules' `service_package_publish`, which pins this tag's specs and the image by digest. The package version is the release tag, as for the image. The stack keeps its state where the organization secrets `PACKAGE_STATE_AWS_ACCOUNT_ID`, `PACKAGE_TFSTATE_BUCKET` and `PACKAGE_TFSTATE_REGION` point; the state role is `github-actions-<repository>-package-state` in that account, by convention.

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
