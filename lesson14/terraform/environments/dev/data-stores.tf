# Data stores and messaging: one PostgreSQL instance (a schema per service), the cart table, the order-events topic.
module "rds" {
  source = "../../modules/rds-postgres"

  name                    = local.name
  vpc_id                  = module.network.vpc_id
  subnet_ids              = module.network.private_subnet_ids
  instance_class          = var.db_instance_class
  db_name                 = "shop"
  username                = "shop_admin"
  multi_az                = var.multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
}

# The only paths into the database: from the task SGs of the services that own a schema, and from db-init.
resource "aws_vpc_security_group_ingress_rule" "db_from_service" {
  for_each = local.db_services

  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.service[each.key].security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from ${each.key}"
}

# Separate from db_from_service: db-init runs before the services exist (terraform_data.db_init waits for this rule).
resource "aws_vpc_security_group_ingress_rule" "db_from_db_init" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.db_init.security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from db-init"
}

moved {
  from = aws_vpc_security_group_ingress_rule.db_from_service["db-init"]
  to   = aws_vpc_security_group_ingress_rule.db_from_db_init
}

module "cart_table" {
  source = "../../modules/dynamodb-table"

  name          = "${local.name}-cart"
  hash_key      = "customer_sub"
  ttl_attribute = "ttl"
}

module "messaging" {
  source = "../../modules/messaging"

  name = local.name
  consumers = {
    payment      = ["OrderCreated"]
    order        = ["PaymentSucceeded", "PaymentFailed"]
    notification = ["OrderCreated", "PaymentSucceeded", "PaymentFailed"]
  }
}
