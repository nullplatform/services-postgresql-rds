# Discover shared RDS infrastructure (tagged by nullplatform during setup)

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  tags = {
    "nullplatform/subnet-type" = "private"
  }
}
