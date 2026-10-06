mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

variables {
  cluster_name                         = "my-cluster"
  state_bucket_name                    = "np-rds-state"
  agent_role_arn                       = ""
  additional_agent_role_arns           = []
  iam_create_role                      = true
  attach_metrics_policy_to_agent_roles = true
}

run "attaches_the_metrics_policy_to_the_default_agent_role" {
  command = apply

  assert {
    condition     = keys(aws_iam_role_policy_attachment.agent_rds_postgres_server_metrics) == ["nullplatform-my-cluster-agent-role"]
    error_message = "the metrics policy must be attached to the derived agent role"
  }

  assert {
    condition     = jsondecode(aws_iam_policy.nullplatform_rds_postgres_server_metrics[0].policy).Statement[0].Action == ["cloudwatch:GetMetricStatistics"]
    error_message = "the metrics policy must grant only cloudwatch:GetMetricStatistics"
  }
}

run "attaches_it_to_every_agent_role_including_role_paths" {
  command = apply

  variables {
    agent_role_arn             = "arn:aws:iam::123456789012:role/custom-agent"
    additional_agent_role_arns = ["arn:aws:iam::123456789012:role/team/path/other-agent"]
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.agent_rds_postgres_server_metrics)) == toset(["custom-agent", "other-agent"])
    error_message = "the metrics policy must be attached to every agent role, by role name"
  }
}

run "creates_nothing_when_disabled" {
  command = apply

  variables {
    attach_metrics_policy_to_agent_roles = false
  }

  assert {
    condition     = length(aws_iam_policy.nullplatform_rds_postgres_server_metrics) == 0 && length(aws_iam_role_policy_attachment.agent_rds_postgres_server_metrics) == 0
    error_message = "the metrics policy must not be created when disabled"
  }
}

run "creates_nothing_when_the_module_creates_no_role" {
  command = apply

  variables {
    iam_create_role = false
  }

  assert {
    condition     = length(aws_iam_policy.nullplatform_rds_postgres_server_metrics) == 0 && length(aws_iam_role_policy_attachment.agent_rds_postgres_server_metrics) == 0
    error_message = "iam_create_role = false must keep the module from creating anything"
  }
}
