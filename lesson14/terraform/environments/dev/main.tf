module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr               = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = var.single_nat_gateway
}

module "cluster" {
  source = "../../modules/ecs-cluster"

  name               = local.name
  container_insights = var.container_insights
}

# One repository per service image plus the one-off db-init image: lesson14/<service>.
module "ecr" {
  source = "../../modules/ecr"

  names        = [for s in setunion(local.services, ["db-init"]) : "${var.project}/${s}"]
  force_delete = var.force_destroy
}

module "cognito" {
  source = "../../modules/cognito"

  name = local.name
}

module "alb" {
  source = "../../modules/alb-internal"

  name                 = "l14-dev" # target groups become l14-dev-<service> (32-character limit)
  vpc_id               = module.network.vpc_id
  vpc_cidr             = module.network.vpc_cidr
  subnet_ids           = module.network.private_subnet_ids
  origin_verify_secret = random_password.origin_verify.result
  services             = local.web_services
}

# VPC Link ENIs may only talk to the ALB on port 80; the ALB SG already accepts port 80 from the VPC CIDR.
resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpc-link"
  description = "API Gateway VPC Link ENIs to the internal ALB"
  vpc_id      = module.network.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  referenced_security_group_id = module.alb.security_group_id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "HTTP to the internal ALB listener"
}

module "api" {
  source = "../../modules/api-gateway"

  name                       = local.name
  vpc_link_subnet_ids        = module.network.private_subnet_ids
  vpc_link_security_group_id = aws_security_group.vpc_link.id
  listener_arn               = module.alb.listener_arn
  jwt_issuer                 = module.cognito.issuer
  jwt_audience               = [module.cognito.client_id]
  public_routes              = local.public_routes
  protected_routes           = local.protected_routes
  log_retention_days         = var.log_retention_days
}

module "waf" {
  source    = "../../modules/waf"
  providers = { aws = aws.us_east_1 }

  name        = local.name
  alarm_email = var.alarm_email
}

locals {
  web_acl_arn = module.waf.web_acl_arn # attached to the distribution: HTTP APIs cannot carry WAF themselves
}

module "edge" {
  source = "../../modules/s3-cloudfront"

  name                 = local.name
  api_host             = module.api.api_host
  origin_verify_secret = random_password.origin_verify.result
  web_acl_arn          = local.web_acl_arn
  force_destroy        = var.force_destroy
}

module "observability" {
  source = "../../modules/observability"

  name                      = local.name
  aws_region                = var.aws_region
  alb_arn_suffix            = module.alb.alb_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  cluster_name              = module.cluster.cluster_name
  service_names             = { for k, s in module.service : k => s.service_name }
  desired_counts            = { for k in local.services : k => var.desired_count }
  db_identifier             = local.name # rds-postgres uses its name as the instance identifier
  db_max_connections        = module.rds.max_connections_estimate
  dlq_names                 = module.messaging.dlq_names
  api_id                    = module.api.api_id
  web_acl_name              = module.waf.web_acl_name
  distribution_id           = module.edge.distribution_id
  alarm_email               = var.alarm_email
}

# SES sandbox: AWS emails a verification link to this address; Notification sends only after it is clicked.
resource "aws_sesv2_email_identity" "sender" {
  count = var.notify_from_email == null ? 0 : 1

  email_identity = var.notify_from_email
}
