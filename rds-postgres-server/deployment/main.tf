# ---------------------------------------------------------------------------
# Security group for RDS (allows PostgreSQL traffic from within the VPC)
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "np-rds-${var.instance_name}"
  description = "Allow PostgreSQL access from within the VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    # Use every CIDR block associated with the VPC, not just the primary one.
    # EKS clusters commonly add a secondary CIDR for pod networking (e.g. a
    # 100.x.x.x block alongside the primary 10.x.x.x one) — pods get IPs from
    # the secondary block, so restricting to the primary CIDR silently blocks
    # agent-pod-to-RDS connectivity. Confirmed live: pod IP 100.17.11.188 vs
    # RDS SG only allowing 10.16.0.0/16.
    cidr_blocks = [for c in data.aws_vpc.main.cidr_block_associations : c.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

# ---------------------------------------------------------------------------
# Master password (stored in Secrets Manager, used by link permissions)
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "nullplatform/rds/${var.instance_name}/master"
  recovery_window_in_days = 0

  tags = {
    "managed-by"   = "nullplatform"
    "rds-instance" = var.instance_name
    "service-id"   = var.service_id
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = "master"
    password = random_password.master.result
  })
}

# ---------------------------------------------------------------------------
# KMS key for RDS storage encryption (customer managed, for parity with the
# Aurora module — the default AWS-managed RDS key works but isn't ours to
# control key policy/rotation on)
# ---------------------------------------------------------------------------

resource "aws_kms_key" "rds" {
  description         = "Customer managed key for RDS instance storage encryption (${var.instance_name})"
  enable_key_rotation = true

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/nullplatform-rds-${var.instance_name}"
  target_key_id = aws_kms_key.rds.key_id
}

# ---------------------------------------------------------------------------
# RDS instance
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = var.instance_name
  subnet_ids = data.aws_subnets.private.ids

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }
}

resource "aws_db_instance" "main" {
  identifier        = var.instance_name
  engine            = "postgres"
  engine_version    = var.postgres_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name  = "postgres"
  username = "master"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.multi_az
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  tags = {
    "managed-by" = "nullplatform"
    "service-id" = var.service_id
  }

  depends_on = [aws_secretsmanager_secret_version.master]
}
