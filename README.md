# services-postgresql-rds

nullplatform service definitions for AWS RDS PostgreSQL:

- [`rds-postgres-server/`](rds-postgres-server/README.md) — provisions the RDS
  PostgreSQL instance itself.
- [`rds-postgres-db/`](rds-postgres-db/README.md) — provisions a database +
  application user on an existing `rds-postgres-server` instance, linked via
  the `connect` link.

Each service directory is self-contained: `entrypoint/`, `workflows/`,
`scripts/` and `specs/` are what its worker image runs, and `publish/` is the
stack that publishes it as a global package on every release (`np-rds-postgres`
and `np-rds-postgres-db`, both at the release version). `specs/requirements/aws/`
is the one-time IAM setup an organization applies before installing the package;
see each service's README, "Install in your organization".

This repository was extracted from `nullplatform/services` (the
`databases/rds-postgres-server` and `databases/rds-postgres-db` directories),
preserving their commit history.
