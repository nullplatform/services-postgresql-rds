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

- An active nullplatform account with at least one **provider** exposing:
  - `account.region` — the AWS region where the RDS instance will be created
  - `vpc.id` — the VPC where the RDS instance will be placed
- The VPC must have private subnets tagged with `nullplatform/subnet-type=private`

### AWS IAM Permissions

The agent executing this service needs the following IAM permissions (see `requirements/main.tf`):

- **RDS**: `CreateDBInstance`, `DeleteDBInstance`, `ModifyDBInstance`, `DescribeDBInstances`, subnet group management, tagging
- **EC2**: Security group management, `DescribeVpcs`, `DescribeSubnets`
- **Secrets Manager**: Full lifecycle (`CreateSecret`, `DeleteSecret`, `GetSecretValue`, `PutSecretValue`, etc.)
- **S3**: Full lifecycle on the `np-service-<SERVICE_ID>` bucket
- **IAM**: `CreateServiceLinkedRole` (for RDS)

The `requirements/` Terraform module can be used to create and attach the necessary IAM policies to an existing role.

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
