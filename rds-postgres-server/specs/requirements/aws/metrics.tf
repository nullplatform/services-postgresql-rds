# -----------------------------------------------------------------------------
# CloudWatch read permission for the service metrics — granted to the AGENT
# role directly, not to the rds-postgres-server permissions role.
#
# Every other action of this service (create, update, link, delete) first
# assumes the rds-postgres-server permissions role created by this module.
# Metrics do not: the metrics view requests all the metrics of an instance at
# once, and every extra step per request (the np provider lookup for the role
# ARN, the sts AssumeRole call, each AWS CLI start) added seconds of latency to
# each graph.
# For timing reasons metrics run on the agent's own credentials and make a
# single call, cloudwatch:GetMetricStatistics. That is why this policy is
# attached to agent_role_arn and additional_agent_role_arns instead of being
# part of the permissions role.
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "nullplatform_rds_postgres_server_metrics" {
  count = local.attach_metrics_policy ? 1 : 0

  name        = "${local.policies_name_prefix}-rds-postgres-server-metrics-policy"
  description = "CloudWatch reads the nullplatform agent makes, on its own credentials, to show rds-postgres-server metrics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadInstanceMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = "*"
      },
    ]
  })

  tags = local.iam_default_tags
}

resource "aws_iam_role_policy_attachment" "agent_rds_postgres_server_metrics" {
  for_each = local.attach_metrics_policy ? local.agent_role_names : toset([])

  role       = each.value
  policy_arn = aws_iam_policy.nullplatform_rds_postgres_server_metrics[0].arn
}
