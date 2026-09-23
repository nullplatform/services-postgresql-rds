locals {
  iam_module_name = "requirements-rds-postgres-db"
  iam_create      = var.iam_create_role

  role_name            = var.role_name != "" ? var.role_name : "nullplatform-${var.cluster_name}-rds-postgres-db-role"
  policies_name_prefix = var.policies_name_prefix != "" ? var.policies_name_prefix : "nullplatform-${var.cluster_name}"
  agent_role_arn       = var.agent_role_arn != "" ? var.agent_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nullplatform-${var.cluster_name}-agent-role"

  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "rds-postgres-db"
    Module    = local.iam_module_name
  })
}

locals {
  # Access to the state bucket the operator names. Nothing here assumes a bucket
  # naming convention: the role is granted on that bucket and nothing else.
  shared_state_statements = [
    {
      "Effect" : "Allow",
      "Action" : ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetBucketLocation"],
      "Resource" : ["arn:aws:s3:::${var.state_bucket_name}"]
    },
    {
      "Effect" : "Allow",
      "Action" : [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource" : ["arn:aws:s3:::${var.state_bucket_name}/*"]
    },
  ]

  # The deprecated bucket-per-instance layout, off unless an operator is still
  # migrating instances off it.
  legacy_state_statements = var.grant_legacy_per_instance_buckets ? [
    {
      "Effect" : "Allow",
      "Action" : [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketVersioning",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource" : [
        "arn:aws:s3:::np-service-*",
        "arn:aws:s3:::np-service-*/*"
      ]
    },
  ] : []
}
