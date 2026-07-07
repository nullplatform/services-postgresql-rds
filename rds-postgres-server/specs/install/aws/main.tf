################################################################################
# Install — registers the rds-postgres-server service definition and its
# agent association (notification channel) on a nullplatform account, and
# (optionally) the account-level providers the "nullplatform Prerequisites"
# section of ../../../README.md documents as required:
#
#   - aws-configuration / aws-networking-configuration (account-level NRN):
#     build_context resolves account.region and vpc.id from these. Toggle
#     with create_account_providers — skip if another stack in this account
#     already registers them (they are shared, not specific to this service).
#   - aws-iam-configuration (account-level NRN): the AssumeRole target for
#     scripts/aws/assume_role_step, which resolves it via `np provider list
#     --categories identity-access-control` using the service's full NRN —
#     that call walks UP the NRN hierarchy, so registering this provider at
#     the account level (rather than namespace/application) is what makes it
#     resolve for every service/namespace under the account. This module is
#     the ONLY place that should create it for the account — the underlying
#     nullplatform_provider_config resource is a plain create with no
#     merge/upsert semantics, so a second, independent identity_access_control
#     resource (e.g. one created by rds-postgres-db's own install) would
#     register a SECOND aws-iam-configuration provider at the same NRN, and
#     assume_role_step's lookup would then nondeterministically pick one of
#     the two. rds-postgres-db does NOT create its own — pass its role ARN
#     via rds_postgres_db_role_arn to fold its selector into this single
#     provider instead.
#
# The AWS AssumeRole IAM role/policies themselves (the permissions role this
# provider points at) live in ../../requirements/aws and are applied
# separately — see that module's README and the "AssumeRole Setup Guide" in
# ../../../README.md.
################################################################################

locals {
  service_path      = "rds-postgres-server"
  available_links   = ["connect"]
  available_actions = []

  account_nrn = replace(var.nrn, "/:namespace=[^:]*/", "")

  iam_role_arns = concat(
    [{ selector = "rds-postgres-server", arn = var.rds_postgres_server_role_arn }],
    var.rds_postgres_db_role_arn != "" ? [{ selector = "rds-postgres-db", arn = var.rds_postgres_db_role_arn }] : []
  )
}

module "service_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition?ref=v4.5.1"

  nrn               = var.nrn
  repository_org    = var.repository_org
  repository_name   = var.repository_name
  repository_branch = var.repository_branch
  repository_token  = var.repository_token
  service_path      = local.service_path
  service_name      = var.service_name
  available_links   = local.available_links
  available_actions = local.available_actions
}

module "service_definition_agent_association" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition_agent_association?ref=v4.5.1"

  nrn                          = var.nrn
  repository_service_spec_repo = "${var.repository_org}/${var.repository_name}"
  service_path                 = local.service_path
  service_specification_slug   = module.service_definition.service_specification_slug
  api_key                      = var.np_api_key
  tags_selectors               = var.tags_selectors
}

# --- account-level providers: account.region + vpc.id ------------------------
# Registered at the account NRN (var.nrn with :namespace=... stripped), same
# as the manual examples in ../../../README.md. Typically applied once per
# cluster/account — set create_account_providers = false if another stack
# already registers these (e.g. shared with non-RDS services).

module "aws_cloud_provider" {
  count = var.create_account_providers ? 1 : 0

  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v5.3.1"

  nrn                    = local.account_nrn
  domain_name            = var.domain_name
  hosted_private_zone_id = var.hosted_private_zone_id
}

module "vpc_provider" {
  count = var.create_account_providers ? 1 : 0

  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/vpc?ref=v5.3.1"

  nrn                 = local.account_nrn
  vpc_id              = var.vpc_id
  vpc_subnets         = var.vpc_subnets
  vpc_security_groups = var.vpc_security_groups
}

# --- account-level provider: AssumeRole target -------------------------------
# See the comment at the top of this file — this is the single source of the
# aws-iam-configuration provider for the account; fold rds-postgres-db's role
# in via rds_postgres_db_role_arn instead of registering it separately.

module "identity_access_control" {
  count = var.create_identity_access_control ? 1 : 0

  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/identity-access-control?ref=v5.3.1"

  nrn = local.account_nrn
  attributes = {
    iam_role_arns = {
      arns = local.iam_role_arns
    }
  }
}
