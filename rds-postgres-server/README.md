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
- **Provider resolution**: reads `account.region` and `vpc.id` from account-level nullplatform providers at creation time
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

> `postgres_version` cannot be changed after creation because PostgreSQL major version upgrades require manual intervention and are not managed by this service.

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
| `aws_db_subnet_group` | Subnet group using VPC subnets tagged `nullplatform/subnet-type=private` |
| `aws_security_group` | Allows port 5432 ingress from within the VPC |
| `aws_secretsmanager_secret` | Stores the master PostgreSQL password |
| `aws_s3_bucket` | `np-service-<SERVICE_ID>` — versioned bucket for Terraform state |
| `postgresql_database` | One per link — isolated database per application link |
| `postgresql_role` | One per link — isolated PostgreSQL user per application link |

## Requirements

### nullplatform Prerequisites

- An active nullplatform account with the following providers configured for the target namespace/dimensions:
  - **`aws-configuration`** (from `tofu-modules//nullplatform/cloud/aws/cloud`) — exposes `account.region`. `build_context` resolves this via `np provider list --nrn <account-level NRN>` filtered by `stored_keys` containing `account.region`.
  - **`aws-networking-configuration`** (from `tofu-modules//nullplatform/cloud/aws/vpc`) — exposes `vpc.id`, `vpc.subnets`, `vpc.security_groups`. Same lookup mechanism, filtered by `vpc.id`.
- The VPC must have private subnets tagged with `nullplatform/subnet-type=private`.
- For AssumeRole to work (not just fail open to agent credentials — see below): an **`aws-iam-configuration`** provider (from `tofu-modules//nullplatform/identity-access-control`) registered at the **namespace-level NRN**.

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

`vpc_subnets`/`vpc_security_groups` don't need to be scoped down to only
what this service uses — pass whatever the cluster's VPC provider already
uses for other scopes/services (e.g. all node/pod subnets and the cluster
security group). This service only reads `vpc.id` from this provider; the
actual subnets it deploys into come separately from
`data.aws_subnets.private` (filtered by the `nullplatform/subnet-type=private`
tag, not from this provider's `vpc_subnets` list).

### AWS IAM Permissions

The agent executing this service needs the following IAM permissions (see `requirements/main.tf`):

- **RDS**: `CreateDBInstance`, `DeleteDBInstance`, `ModifyDBInstance`, `DescribeDBInstances`, subnet group management, tagging
- **EC2**: Security group management, `DescribeVpcs`, `DescribeSubnets`
- **Secrets Manager**: Full lifecycle (`CreateSecret`, `DeleteSecret`, `GetSecretValue`, `PutSecretValue`, etc.)
- **S3**: Full lifecycle on the `np-service-<SERVICE_ID>` bucket
- **IAM**: `CreateServiceLinkedRole` (for RDS)

The `requirements/` Terraform module creates a dedicated IAM role
(`nullplatform-<cluster_name>-rds-postgres-server-role`) holding these
policies, with a trust policy allowing the nullplatform agent role to
`sts:AssumeRole` on it. Pass `cluster_name` (required) and optionally
`agent_role_arn` (defaults to `nullplatform-<cluster_name>-agent-role`) when
applying it. Granting the agent itself permission to assume this role is
handled separately, outside this module.

### AssumeRole Setup Guide

Three separate pieces must all be in place for the agent to actually assume
`nullplatform-<cluster_name>-rds-postgres-server-role` at runtime — applying
`requirements/` alone is not enough:

1. **Apply `requirements/`** with `cluster_name` (and optionally
   `agent_role_arn`) — creates the role and its trust policy (see above):
   ```hcl
   module "service_requirements_rds_postgres_server" {
     source = "git::https://github.com/nullplatform/services.git//databases/rds-postgres-server/requirements?ref=<tag>"

     cluster_name = "<cluster-name>"
     # agent_role_arn = ""  # optional override; defaults to
     #   arn:aws:iam::<account-id>:role/nullplatform-<cluster-name>-agent-role
   }
   ```
   Read `module.service_requirements_rds_postgres_server.permissions_role_arn`
   for the ARN needed in steps 2 and 3 below.
2. **Grant the agent permission to assume it.** Not managed by
   `requirements/` — add an inline (or managed) policy to the **agent's own**
   IAM role:
   ```json
   {
     "Effect": "Allow",
     "Action": "sts:AssumeRole",
     "Resource": "arn:aws:iam::<account-id>:role/nullplatform-<cluster_name>-rds-postgres-server-role"
   }
   ```
3. **Register the role as an `identity-access-control` provider** in
   nullplatform, at the **namespace-level NRN**
   (`organization=...:account=...:namespace=...` — without `:application=...`),
   with selector `rds-postgres-server`:
   ```hcl
   module "identity_access_control" {
     source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/identity-access-control?ref=<tag>"
     nrn    = "organization=<org>:account=<account>:namespace=<namespace>"
     attributes = {
       iam_role_arns = {
         arns = [{ selector = "rds-postgres-server", arn = "<role ARN from step 1>" }]
       }
     }
   }
   ```

`scripts/aws/assume_role_step` resolves the role by querying
`np provider list` / `np provider read` for this provider at the service's
**namespace NRN** — not by reading `CONTEXT.providers[...]`. This was
confirmed live: this platform's agent never populates `CONTEXT.providers`
regardless of the `provider_categories` declared in `values.yaml` or the
workflow YAMLs, so the lookup goes through the `np` CLI directly instead
(the same mechanism `build_context` already uses for the region/VPC
providers above).

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

### Storage Encryption

All RDS instances are created with `storage_encrypted = true` using the default AWS-managed key.

### Terraform State

Terraform state is stored in an S3 bucket named `np-service-<SERVICE_ID>` with versioning enabled. This bucket is created before provisioning and deleted (including all versions) after the RDS instance is destroyed.
