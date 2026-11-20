# rds-postgres-server

A nullplatform dependency service that provisions and manages a shared **Amazon RDS PostgreSQL instance** on AWS. It acts as the infrastructure layer in a two-tier database architecture, creating the actual RDS instance that one or more [`rds-postgres-db`](../rds-postgres-db) services consume.

## What It Does

- Provisions an RDS PostgreSQL instance inside a VPC using Terraform (via OpenTofu)
- Stores the master password in AWS Secrets Manager
- Creates a dedicated security group allowing port 5432 within the VPC
- Manages per-link databases and users: each link to an application creates a dedicated PostgreSQL database and user with scoped grants
- Stores connection metadata in nullplatform service attributes so linked services can discover the endpoint

## Architecture

```
nullplatform Application
        │
        │ link (creates DB + user)
        ▼
rds-postgres-server  ──────► AWS RDS PostgreSQL Instance
  (this service)              │  └─ Security Group (port 5432, VPC-scoped)
        │                     │  └─ Secrets Manager (master password)
        │                     │  └─ S3 Bucket (Terraform state)
        └─ per link:
             postgresql_database.<link_name>
             postgresql_role.<link_name>
             postgresql_grant.*
```

## Nullplatform Integration

This service integrates with nullplatform through:

- **Dependency service type**: registered as a `dependency` service in nullplatform
- **Provider resolution**: reads `account.region` and `vpc.id` from the nullplatform providers that resolve for the service NRN and dimensions; an existing instance keeps the VPC and region recorded in its state
- **Service attributes**: writes RDS connection metadata back to nullplatform via `np service patch` after provisioning
- **Link attributes**: writes per-link DB credentials to link attributes via `np link patch` so applications can consume them as environment variables
- **Dimension matching**: supports nullplatform dimensions so multiple environments (e.g., `cluster: prod`, `cluster: staging`) can have isolated RDS instances

### Service Attributes (written after create)

| Attribute | Visibility | Description |
|---|---|---|
| `hostname` | exported | RDS endpoint hostname |
| `port` | exported | RDS port (5432) |
| `db_instance_identifier` | internal | AWS RDS resource identifier |
| `master_secret_arn` | internal | Secrets Manager ARN for master credentials |

### Link Attributes (written per link)

| Attribute | Description |
|---|---|
| `username` | PostgreSQL user for this link |
| `password` | PostgreSQL password (injected as secret) |
| `database_name` | PostgreSQL database name for this link |
| `hostname` | RDS endpoint hostname |
| `port` | RDS port |

## Configuration Parameters

Exposed in the nullplatform UI when creating or updating the service:

| Parameter | Type | Default | Allowed Values | Editable After Create |
|---|---|---|---|---|
| `instance_class` | string | `db.t3.micro` | `db.t3.micro`, `db.t3.small`, `db.t3.medium`, `db.m5.large` | Yes |
| `allocated_storage` | number | `20` | 20–1000 (GB) | Yes |
| `postgres_version` | string | `16` | `14`, `15`, `16` | No |
| `secret_kms_key_id` | string | _(none)_ | Any KMS key ID/ARN in the account | Yes |

> `postgres_version` cannot be changed after creation because PostgreSQL major version upgrades require manual intervention and are not managed by this service.

> `secret_kms_key_id` controls which KMS key encrypts the master password secret in Secrets Manager. If left unset, AWS encrypts it with the default `aws/secretsmanager` managed key — pass a customer-managed key ARN here only if this service instance requires its own key.

## Workflows

| Workflow | Trigger | What It Does |
|---|---|---|
| `create` | Service created | Provisions RDS instance, security group, Secrets Manager secret, S3 tfstate bucket |
| `update` | Service updated | Applies Terraform changes (instance class, storage) |
| `delete` | Service deleted | Destroys RDS instance and all associated resources; **no final snapshot is taken** |
| `link` | Application linked | Creates a PostgreSQL database + user with `CONNECT`, `USAGE`, and DML grants |
| `unlink` | Application unlinked | Revokes grants only; database and user are **preserved** for data retention |

## Infrastructure Resources Created

| Resource | Description |
|---|---|
| `aws_db_instance` | The RDS PostgreSQL instance (gp3 storage, encrypted, no public access) |
| `aws_db_subnet_group` | Subnet group using `vpc.subnets` of the `vpc` provider |
| `aws_security_group` | Allows port 5432 ingress from within the VPC |
| `aws_secretsmanager_secret` | Stores the master PostgreSQL password |
| `aws_s3_bucket` | only in the deprecated fallback: `np-service-<SERVICE_ID>`, a versioned bucket for Terraform state |
| `postgresql_database` | One per link — isolated database per application link |
| `postgresql_role` | One per link — isolated PostgreSQL user per application link |

## Requirements

### nullplatform Prerequisites

- The package installed in the organization, with its agent channel — see
  [Install in your organization](#install-in-your-organization) below.
- An active nullplatform account with the following providers configured for the target namespace/dimensions:
  - **`aws-configuration`** (from `tofu-modules//nullplatform/cloud/aws/cloud`) — exposes `account.region`. `build_context` resolves this via `np provider list --nrn <service NRN> --categories cloud-providers --dimensions <service dimensions>`.
  - **`aws-networking-configuration`** (from `tofu-modules//nullplatform/cloud/aws/vpc`) — exposes `vpc.id`, `vpc.subnets`, `vpc.security_groups`. Same lookup mechanism, with `--categories vpc`.
- The `vpc` provider must list in `vpc.subnets` at least two private subnets in different availability zones; `build_context` stops before tofu otherwise.
- For AssumeRole to work (not just fail open to agent credentials — see below): an **`aws-iam-configuration`** provider (from `tofu-modules//nullplatform/identity-access-control`) registered at the **account-level NRN** (or any ascendant of the service's NRN — resolution walks up the hierarchy).

Example registering the `aws-configuration` and `aws-networking-configuration`
providers (typically applied once per cluster/account, at the account-level
NRN — no `:namespace=...`):

```hcl
module "aws_cloud_provider" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=<tag>"

  nrn                     = "organization=<org>:account=<account>"
  domain_name             = "<your-domain>"
  hosted_private_zone_id  = "<private-hosted-zone-id>"
}

module "vpc_provider" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/vpc?ref=<tag>"

  nrn                 = "organization=<org>:account=<account>"
  vpc_id              = "<vpc-id>"
  vpc_subnets         = ["<private-subnet-id-1>", "<private-subnet-id-2>", "..."]
  vpc_security_groups = ["<node/cluster-security-group-id>", "..."]
}
```

The RDS subnet group is built from this provider's `vpc_subnets`, so list
the private subnets the database should live in. An instance that already
exists keeps the subnets recorded in its state.

### AWS IAM Permissions

The agent executing this service needs the following IAM permissions (see `specs/requirements/aws/main.tf`):

- **RDS**: `CreateDBInstance`, `DeleteDBInstance`, `ModifyDBInstance`, `DescribeDBInstances`, subnet group management, tagging
- **EC2**: Security group management, `DescribeVpcs`, `DescribeSubnets`
- **Secrets Manager**: Full lifecycle (`CreateSecret`, `DeleteSecret`, `GetSecretValue`, `PutSecretValue`, etc.)
- **S3**: read/write on the state bucket named by `state_bucket_name`, and nothing else
- **IAM**: `CreateServiceLinkedRole` (for RDS)

The `requirements/` Terraform module creates a dedicated IAM role
(`nullplatform-<cluster_name>-rds-postgres-server-role`) holding these
policies, with a trust policy allowing the nullplatform agent role to
`sts:AssumeRole` on it. Pass `cluster_name` (required) and optionally
`agent_role_arn` (defaults to `nullplatform-<cluster_name>-agent-role`),
`role_name` (defaults to `nullplatform-<cluster_name>-rds-postgres-server-role`)
and `policies_name_prefix` (defaults to `nullplatform-<cluster_name>`) when
applying it. Granting the agent itself permission to assume this role is
handled separately, outside this module.

### Install in your organization

The service is published once as the package `np-rds-postgres` (specification "RDS PostgreSQL"), visible to every organization. You do not copy its specs: you install the package and use it read-only. How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this service.

Already registered a copy from the former `specs/install`? It keeps working: it called tofu-modules' `service_definition` on specs that stay in every release, and the package installs next to it, as the guide explains. If you sourced that directory as a module, pin its `?ref` to a release that still has it.

Installing it touches the same three layers as registering a service yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (AWS credentials) | The IAM role the service assumes, with access to the state bucket | [`specs/requirements/aws`](specs/requirements/aws) |
| nullplatform (nullplatform API key) | The installation of the package and the agent channel | tofu-modules' `service_package_installation` |
| bindings | The role under selector `rds-postgres-server` in your IAM provider | your `aws-iam-configuration` provider |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/services-postgresql-rds/releases)) and use its version in both places below: the IAM role is the one the worker of that same release expects. Both services of this repository share the release, so install them at the same version.

```hcl
# ── infrastructure layer ─────────────────────────────────────────────
module "rds_postgres_server_requirements" {
  source            = "git::https://github.com/nullplatform/services-postgresql-rds.git//rds-postgres-server/specs/requirements/aws?ref=vX.Y.Z"
  cluster_name      = "<nullplatform agent cluster>"
  state_bucket_name = "<existing S3 bucket for the tofu state>"
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.rds_postgres_server_requirements.permissions_role_arn]

# ── nullplatform layer ───────────────────────────────────────────────
# For a service the installation is the whole nullplatform side, channel included.
module "rds_postgres_server" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_package_installation?ref=v9.16.0"

  nrn                  = var.nrn
  package_slug         = "np-rds-postgres"
  package_version      = "X.Y.Z" # the same release, without the v
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}
# Keeping channels in a separate bindings layer instead? Use
# nullplatform/package_installation here and service_definition_agent_association
# there, with package_slug = "np-rds-postgres".

# ── bindings layer ───────────────────────────────────────────────────
# One aws-iam-configuration per NRN and dimensions, at the account level: add
# the entry to the list your IAM provider already has. Both services of this
# repository go in the SAME provider, one selector each.
#   { selector = "rds-postgres-server", arn = module.rds_postgres_server_requirements.permissions_role_arn }
```

**The state bucket.** Set `RDS_POSTGRES_S3_STATE_BUCKET` on the worker (a per-package env patch in tofu-modules' `nullplatform/agent`) to the name of an existing S3 bucket, and pass the same name to the requirements module as `state_bucket_name`. Every instance keeps its Terraform state there under `services/rds-postgres/<service-id>/`; both services share the bucket and the service id keeps their keys apart. The bucket must already exist: the service never creates or deletes it, and without the variable every action fails before touching AWS.

The service assumes the role it finds under selector `rds-postgres-server` in the IAM provider closest to its NRN. To upgrade, move the release in both layers: `ref` of the requirements module and `package_version` of the installation. See tofu-modules' [`service_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/service_package_installation) for its inputs and outputs.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries` and `np-rds-postgres` in its `worker_orchestrated_packages` (the worker then runs with the agent's identity, the one the role trusts), and the `aws-configuration` and `aws-networking-configuration` providers above at the NRN or above it.

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
under the **agent's own role** — which fails with `AccessDenied` on
RDS/EC2/Secrets Manager/S3 calls unless the agent happens to have those
permissions directly attached (the old, pre-AssumeRole model). This
fail-open behavior is intentional (mirrors `nullplatform/scopes-static-files`),
but it means a misconfigured AssumeRole setup fails *silently* as what looks
like a permissions problem rather than a missing-provider problem — check
the `assume role` step's log line first when debugging `AccessDenied`
errors from later steps.

### How the package is published

Every release publishes a new revision of the package from this repository, in the same run that pushes the worker image ([`.github/workflows/release.yml`](../.github/workflows/release.yml)): the `publish-package` job applies [`rds-postgres-server/publish`](publish), a stack on tofu-modules' `service_package_publish`, which pins this tag's specs and the image by digest. The package version is the release tag, as for the image. The stack keeps its state where the organization secrets `PACKAGE_STATE_AWS_ACCOUNT_ID`, `PACKAGE_TFSTATE_BUCKET` and `PACKAGE_TFSTATE_REGION` point; the state role is `github-actions-<repository>-package-state` in that account, by convention.

### Networking Requirements

`deployment/main.tf`'s RDS security group allows ingress on 5432 from
**every CIDR block associated with the VPC**
(`data.aws_vpc.main.cidr_block_associations`), not just the primary one.
This matters because EKS clusters commonly add a **secondary CIDR block**
for pod networking (e.g. primary `10.x.x.x` for nodes, secondary
`100.x.x.x` for pods via the AWS VPC CNI's custom networking/prefix
delegation) — agent pods get IPs from the secondary range, not the
primary one. If the VPC has more than one CIDR association, all of them
are allowed automatically; no extra configuration is needed here. Symptom
if this were ever restricted to a single CIDR: any step that touches the
`postgresql` Terraform provider (this service's `db_setup`, or
`rds-postgres-db`'s workflows) **hangs indefinitely** — the TCP connection
attempt to the RDS endpoint never completes or times out quickly, it just
stalls — rather than failing fast with a clear error.

### Runtime Dependencies

These tools are required inside the agent container:

- **OpenTofu 1.9.0** — auto-downloaded to `/tmp/np-tofu-bin/` if not available in `PATH`
- **AWS CLI** — for Secrets Manager and S3 operations
- **jq** — for JSON parsing
- **PostgreSQL client (`psql`)** — installed via `apk add postgresql-client` when needed for link operations

## Important Considerations

### Data Loss on Delete

The service uses `skip_final_snapshot = true`. **Deleting the service permanently destroys all data** in the RDS instance with no automated backup. Ensure manual snapshots are taken before deletion if data recovery is needed.

### Unlink Preserves Data

When an application is unlinked, only the PostgreSQL **grants are revoked** — the database and user are preserved. This prevents accidental data loss when relinking or migrating applications.

### Dimension Alignment

For `rds-postgres-db` services to auto-discover this server, both services must share the same nullplatform dimensions (e.g., `cluster: prod`). Mismatched dimensions will cause discovery to fail.

### Secrets Manager Deletion

The master password secret is deleted immediately on service destroy (`recovery_window_in_days = 0`). There is no recovery window.

### Resource Naming

New instances and their AWS resources are named `<service slug>-<service id>`, e.g. `orders-cacb7da7-9e34-4ba3-be7a-c2a149c23ead`. The slug is truncated so the RDS identifier stays within 63 characters.

An instance that already has a tofu state keeps the name recorded there, so instances created as `np-<service name>` are never renamed (renaming an RDS instance replaces it and loses its data).

### Storage Encryption

All RDS instances are created with `storage_encrypted = true`. By default each instance gets its own customer-managed KMS key.

Set `RDS_POSTGRES_KMS_KEY_ARN` on the agent to encrypt new instances with an existing key instead; no key is created then. The variable only applies while the tofu state has no instance yet: once it exists, its key comes from the state, so setting or changing the variable later never re-encrypts (and so never replaces) an existing instance. List the key in `external_kms_key_arns` of `specs/requirements/aws` so the role can use it.

### Terraform State

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

