# services-postgresql-rds

nullplatform service definitions for AWS RDS PostgreSQL:

- [`rds-postgres-server/`](rds-postgres-server/README.md) — provisions the RDS
  PostgreSQL instance itself.
- [`rds-postgres-db/`](rds-postgres-db/README.md) — provisions a database +
  application user on an existing `rds-postgres-server` instance, linked via
  the `connect` link.

Each service directory is self-contained: `entrypoint/`, `workflows/`,
`scripts/`, and `specs/` are read directly by the nullplatform agent at
runtime. `specs/requirements/aws/` and `specs/install/aws/` contain one-time
setup Terraform, applied out-of-band by an account operator — see each
service's own README for the full setup guide ("AssumeRole Setup Guide") and
`specs/install/README.md`.

This repository was extracted from `nullplatform/services` (the
`databases/rds-postgres-server` and `databases/rds-postgres-db` directories),
preserving their commit history.
