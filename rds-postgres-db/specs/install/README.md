# Install — registering the rds-postgres-db service

This directory holds the reference OpenTofu/Terraform used to **install**
rds-postgres-db on a nullplatform account: registering its service
specification, link specification, and agent association (notification
channel) so `np service create` starts routing actions to an agent.

This is separate from `../requirements/aws`, which provisions the AWS
AssumeRole IAM role/policies the *agent* needs to operate the service — see
that module's README and the "AssumeRole Setup Guide" in the top-level
[`README.md`](../../README.md) for that half of the setup.

Unlike `rds-postgres-server`'s install, this one does **not** register the
`aws-iam-configuration` provider (the AssumeRole target). That provider is
account-scoped and only additive-by-recreation — a second, independent
registration at the same account NRN would make
`scripts/aws/assume_role_step`'s lookup nondeterministic between the two.
Instead, pass this service's permissions role ARN (the `permissions_role_arn`
output of `../requirements/aws`) as `rds_postgres_db_role_arn` to
[`rds-postgres-server`'s install](../../rds-postgres-server/specs/install/README.md),
which folds both selectors into a single provider.

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
cp -r rds-postgres-db/specs/install/aws /path/to/your/infra/rds-postgres-db
cd /path/to/your/infra/rds-postgres-db
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

tofu init
tofu apply
```

`tags_selectors` must match the tag selectors of the agent(s) that should
pick up rds-postgres-db actions (the same selectors passed as
`tags_selectors` to the `nullplatform/agent` tofu-module).

Run this once per nullplatform namespace, alongside the matching
rds-postgres-server install (see that service's
[`specs/install/README.md`](../../rds-postgres-server/specs/install/README.md)).
It only registers the service with the platform — it does not create any
AWS infrastructure by itself (that happens per-instance, at `create` time,
via `deployment/` and the AssumeRole role from `requirements/aws`).
