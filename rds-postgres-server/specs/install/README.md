# Install — registering the rds-postgres-server service

This directory holds the reference OpenTofu/Terraform used to **install**
rds-postgres-server on a nullplatform account:

- Registers its service specification, link specification, and agent
  association (notification channel) so `np service create` starts routing
  actions to an agent.
- Optionally registers the `aws-configuration` / `aws-networking-configuration`
  providers (account.region, vpc.id) that `build_context` needs — toggle with
  `create_account_providers`, off if another stack already registers them.
- Optionally registers the `aws-iam-configuration` provider (the AssumeRole
  target for `scripts/aws/assume_role_step`) — toggle with
  `create_identity_access_control`. **This is the only place that should
  create it for the account.** If `rds-postgres-db` is also installed,
  pass its permissions role ARN via `rds_postgres_db_role_arn` so both
  selectors land in the same provider — see the comment at the top of
  `aws/main.tf` for why registering it a second time (from rds-postgres-db's
  own install) would break `assume_role_step`'s lookup.

This is separate from `../requirements/aws`, which provisions the AWS
AssumeRole IAM role/policies the *agent* needs to operate the service — the
`rds_postgres_server_role_arn` / `rds_postgres_db_role_arn` variables here
are that module's `permissions_role_arn` output. See that module's README
and the "AssumeRole Setup Guide" in the top-level [`README.md`](../../README.md)
for the full picture.

## Layout

```
install/
├── README.md          (this file)
└── aws/                Working example
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

## Using the example

```bash
cp -r rds-postgres-server/specs/install/aws /path/to/your/infra/rds-postgres-server
cd /path/to/your/infra/rds-postgres-server
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

tofu init
tofu apply
```

`tags_selectors` must match the tag selectors of the agent(s) that should
pick up rds-postgres-server actions (the same selectors passed as
`tags_selectors` to the `nullplatform/agent` tofu-module).

Run this once per nullplatform namespace. It only registers the service
with the platform — it does not create any AWS infrastructure by itself
(that happens per-instance, at `create` time, via `deployment/` and the
AssumeRole role from `requirements/aws`).
