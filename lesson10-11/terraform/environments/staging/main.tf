locals {
  name = "${var.project}-staging"
}

module "network" {
  source = "../../modules/network"
  name   = local.name
  cidr   = var.vpc_cidr
  azs    = var.azs
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "${local.name}-api"
}

module "rds" {
  source                    = "../../modules/rds"
  name                      = local.name
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.private_subnet_ids
  backup_retention_period   = 7
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = var.final_snapshot_identifier
}

module "alb" {
  source       = "../../modules/alb"
  name         = local.name
  vpc_id       = module.network.vpc_id
  vpc_cidr     = var.vpc_cidr
  subnet_ids   = module.network.public_subnet_ids
  allowed_cidr = var.allowed_cidr
}

module "ecs" {
  source           = "../../modules/ecs"
  name             = local.name
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.public_subnet_ids
  assign_public_ip = true # AWS API egress via IGW; inbound is restricted to the ALB SG.
  desired_count    = 2
  image            = "${module.ecr.repository_url}:${var.image_tag}"

  load_balancer = {
    target_group_arn  = module.alb.target_group_arn
    security_group_id = module.alb.security_group_id
  }

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

resource "aws_vpc_security_group_ingress_rule" "db_from_api" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.ecs.security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from staging API tasks"
}
