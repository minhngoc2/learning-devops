resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# No ingress here: the caller decides who may connect (see environments/dev/main.tf).
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL; ingress rules are added by the caller"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

resource "aws_db_instance" "main" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  # RDS generates the password and keeps it in Secrets Manager; it never appears in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  auto_minor_version_upgrade = true # security patches within the pinned major version
  copy_tags_to_snapshot      = true

  backup_retention_period   = var.backup_retention_period
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.name}-final")
}
