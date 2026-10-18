data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"
  name   = local.name
  cidr   = var.vpc_cidr
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = "${var.project}-api"
  force_delete = true # dev: let terraform destroy remove pushed images
}

module "rds" {
  source     = "../../modules/rds"
  name       = local.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # dev/lab settings: cheap and easy to destroy
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 0
}

module "ecs" {
  source           = "../../modules/ecs"
  name             = local.name
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.public_subnet_ids
  assign_public_ip = true # no ALB/NAT: the task's public IP is the API endpoint
  allowed_cidr     = var.allowed_cidr
  image            = "${module.ecr.repository_url}:${var.image_tag}"

  environment = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.db_name
    DB_USER = module.rds.username
  }
  secrets = {
    DB_PASSWORD = "${module.rds.secret_arn}:password::"
  }
}

# The only path into the database: from the API tasks' security group.
resource "aws_vpc_security_group_ingress_rule" "db_from_api" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.ecs.security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from the API tasks"
}
