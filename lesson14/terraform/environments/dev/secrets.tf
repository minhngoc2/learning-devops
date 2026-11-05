# Shared secret proving a request came through CloudFront: CloudFront adds it as X-Origin-Verify, the ALB rules
# require it, and Order Service sends it on its own calls to the ALB.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "origin_verify" {
  name                    = "${local.name}/origin-verify"
  description             = "X-Origin-Verify header value shared by CloudFront, the internal ALB and Order Service"
  recovery_window_in_days = 0 # dev: destroy and re-apply can reuse the name immediately
}

resource "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id     = aws_secretsmanager_secret.origin_verify.id
  secret_string = random_password.origin_verify.result
}

# One PostgreSQL login per DB service (svc_<service>); db-init creates the roles with these passwords.
resource "random_password" "db_role" {
  for_each = local.db_services

  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db_role" {
  for_each = local.db_services

  name                    = "${local.name}/db/${each.key}"
  description             = "Password of PostgreSQL role svc_${each.key}"
  recovery_window_in_days = 0 # dev: destroy and re-apply can reuse the name immediately
}

resource "aws_secretsmanager_secret_version" "db_role" {
  for_each = local.db_services

  secret_id     = aws_secretsmanager_secret.db_role[each.key].id
  secret_string = random_password.db_role[each.key].result
}
