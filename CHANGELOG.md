# Changelog

## [0.1.1](https://github.com/nullplatform/services-postgresql-rds/compare/v0.1.0...v0.1.1) (2026-08-24)


### Bug Fixes

* **rds-postgres-server:** grant KMS permissions for storage encryption CMK ([cd12953](https://github.com/nullplatform/services-postgresql-rds/commit/cd12953d598b817c8f8dda33b252dc9fca9eba82))
* **rds-postgres-server:** grant kms:*Alias on the key resource too ([f4c2125](https://github.com/nullplatform/services-postgresql-rds/commit/f4c21257c7a00d1ac21652c43834f8feb4177589))
* **rds-postgres-server:** grant kms:GetKeyPolicy for CMK read-back ([c3610c6](https://github.com/nullplatform/services-postgresql-rds/commit/c3610c6f738f8a96db3b9dffb27253c2c812f311))
* **rds-postgres-server:** grant kms:ListAliases for alias read-back ([1019ad8](https://github.com/nullplatform/services-postgresql-rds/commit/1019ad8f0561d178a8e4de6c22ebadaab71bd876))
* **rds-postgres-server:** grant tag-scoped KMS permissions for storage encryption ([0a903a4](https://github.com/nullplatform/services-postgresql-rds/commit/0a903a4ed8df97f8f8cf36142bbeacf2b787728a))

## [0.1.0](https://github.com/nullplatform/services-postgresql-rds/compare/v0.0.3...v0.1.0) (2026-08-24)


### Features

* **rds-postgres-server:** make Secrets Manager encryption key configurable ([b20d702](https://github.com/nullplatform/services-postgresql-rds/commit/b20d7021bfbbdc1e3da14ab463184e122f00c5cd))


### Bug Fixes

* **rds-postgres-db:** store app-level credentials in Secrets Manager ([066e333](https://github.com/nullplatform/services-postgresql-rds/commit/066e3337f93853f71caee9bcbcfea391fa2a60c9))

## [0.0.3](https://github.com/nullplatform/services-postgresql-rds/compare/v0.0.2...v0.0.3) (2026-07-28)


### Bug Fixes

* clarify README wording for one-time setup Terraform paths ([0af05ad](https://github.com/nullplatform/services-postgresql-rds/commit/0af05ad375d913e3c1950c47fff2698b8106d594))
* clarify subject-verb agreement for setup Terraform paths in README ([233eeba](https://github.com/nullplatform/services-postgresql-rds/commit/233eeba0bf7193234ad416b8e4a0340882d84a6d))

## [0.0.2](https://github.com/nullplatform/services-postgresql-rds/compare/0.0.1...v0.0.2) (2026-07-28)


### Bug Fixes

* use a customer managed KMS key for RDS storage encryption ([dad747c](https://github.com/nullplatform/services-postgresql-rds/commit/dad747cb3d293e276f3ccd082bc015bd0958159c))
* use a customer managed KMS key for RDS storage encryption ([65f39d3](https://github.com/nullplatform/services-postgresql-rds/commit/65f39d3767f5d55f429e766307e4ab0aa92dd07b))
