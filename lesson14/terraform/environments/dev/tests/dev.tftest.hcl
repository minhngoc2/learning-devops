# Mocked AWS: no credentials or real resources. The random provider is real and generates local passwords.
# Defaults give the computed ARNs/URLs a realistic shape, so module validations see what AWS would return.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-1"
      name   = "ap-southeast-1"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      api_endpoint  = "https://abc123.execute-api.ap-southeast-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:ap-southeast-1:111111111111:abc123"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:loadbalancer/app/l14-dev/0123456789abcdef"
      arn_suffix = "app/l14-dev/0123456789abcdef"
      dns_name   = "internal-l14-dev-123456789.ap-southeast-1.elb.amazonaws.com"
    }
  }
  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:listener/app/l14-dev/0123456789abcdef/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:targetgroup/l14-dev-svc/0123456789abcdef"
      arn_suffix = "targetgroup/l14-dev-svc/0123456789abcdef"
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id          = "E2EXAMPLE"
      arn         = "arn:aws:cloudfront::111111111111:distribution/E2EXAMPLE"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }
  mock_resource "aws_cognito_user_pool" {
    defaults = {
      arn      = "arn:aws:cognito-idp:ap-southeast-1:111111111111:userpool/ap-southeast-1_example"
      endpoint = "cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_example"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-1:111111111111:lesson14-dev-order-events"
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:ap-southeast-1:111111111111:lesson14-dev-queue"
      url = "https://sqs.ap-southeast-1.amazonaws.com/111111111111/lesson14-dev-queue"
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address = "lesson14-dev.abcdefghijkl.ap-southeast-1.rds.amazonaws.com"
      master_user_secret = [{
        secret_arn = "arn:aws:secretsmanager:ap-southeast-1:111111111111:secret:rds!db-0123-AbCdEf"
      }]
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:ap-southeast-1:111111111111:secret:lesson14-dev/secret-AbCdEf"
    }
  }
  mock_resource "aws_secretsmanager_secret_version" {
    defaults = {
      secret_arn = "arn:aws:secretsmanager:ap-southeast-1:111111111111:secret:lesson14-dev/secret-AbCdEf"
    }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:ap-southeast-1:111111111111:table/lesson14-dev-cart"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::lesson14-dev-images-111111111111"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:ap-southeast-1:111111111111:log-group:/lesson14-dev"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/lesson14-dev-role"
    }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::111111111111:function/lesson14-dev-function"
    }
  }
  mock_resource "aws_sesv2_email_identity" {
    defaults = {
      arn = "arn:aws:ses:ap-southeast-1:111111111111:identity/shop@example.com"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/lesson14-dev/0123abcd-0123-abcd-0123-0123456789ab"
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:111111111111:lesson14-dev-waf-ops"
    }
  }
}

# terraform_data.db_init would run scripts/run-db-init.sh (AWS CLI) on every mocked apply.
variables {
  run_db_init = false
}

run "six_services_and_db_init" {
  command = apply

  assert {
    condition = (
      toset(keys(module.service)) == toset(["user", "product", "cart", "order", "payment", "notification"]) &&
      alltrue([for k, s in module.service : s.service_name == "lesson14-dev-${k}" && s.log_group_name == "/ecs/lesson14-dev-${k}"])
    )
    error_message = "Each of the six services must run as an ECS service named lesson14-dev-<service>."
  }
  assert {
    condition     = module.db_init.service_name == null && module.db_init.scalable_target_resource_id == null && module.db_init.task_definition_arn != null
    error_message = "db-init must be a task definition only, with no ECS service or autoscaling."
  }
  assert {
    condition = (
      terraform_data.db_init.triggers_replace == [module.db_init.task_definition_arn] &&
      output.db_init_log_group_name == "/ecs/lesson14-dev-db-init" &&
      output.db_init_log_group_name == module.db_init.log_group_name
    )
    error_message = "terraform_data.db_init must run db-init during apply, re-running when its task definition changes."
  }
  assert {
    condition = (
      toset(keys(output.ecr_repository_urls)) == toset(["user", "product", "cart", "order", "payment", "notification", "db-init"]) &&
      output.service_names["notification"] == "lesson14-dev-notification" &&
      output.cluster_name == "lesson14-dev"
    )
    error_message = "ECR must hold one repository per service plus db-init; outputs must be keyed by service."
  }
  assert {
    condition = (
      strcontains(output.db_init_run_command, "aws ecs run-task --cluster lesson14-dev --launch-type FARGATE --task-definition ") &&
      strcontains(output.db_init_run_command, "assignPublicIp=DISABLED}\"")
    )
    error_message = "db_init_run_command must be a complete aws ecs run-task command in private subnets."
  }
  assert {
    condition = (
      local.service_environment["product"].PUBLIC_BASE_URL == "https://d111111abcdef8.cloudfront.net" &&
      local.service_environment["order"].ALB_URL == "http://internal-l14-dev-123456789.ap-southeast-1.elb.amazonaws.com" &&
      local.service_environment["user"].DB_USER == "svc_user" && local.service_environment["user"].DB_SCHEMA == "users" &&
      toset(keys(local.service_secrets["order"])) == toset(["DB_PASSWORD", "ORIGIN_VERIFY"]) &&
      length(local.service_secrets["cart"]) == 0 &&
      output.cloudfront_url == "https://d111111abcdef8.cloudfront.net"
    )
    error_message = "Services must get their environment and secrets as the table in the plan describes."
  }
  assert {
    condition = (
      length(aws_sesv2_email_identity.sender) == 0 &&
      local.service_environment["notification"].NOTIFY_MODE == "log" &&
      !contains(flatten([for s in jsondecode(local.task_policies["notification"]).Statement : s.Action]), "ses:SendEmail")
    )
    error_message = "Without notify_from_email there must be no SES identity, notification logs emails, and has no ses:SendEmail."
  }
}

run "web_services_registered_on_alb" {
  command = apply

  assert {
    condition     = toset(keys(module.alb.target_group_arns)) == toset(["user", "product", "cart", "order", "payment"])
    error_message = "The ALB must have exactly five target groups, one per web service."
  }
  assert {
    condition = (
      !contains(keys(local.service_target_groups), "notification") &&
      !contains(keys(local.web_services), "notification") &&
      length(local.service_target_groups) == 5
    )
    error_message = "notification is a worker: no target group and no ALB ingress."
  }
}

run "protected_routes_carry_jwt" {
  command = plan

  assert {
    condition     = length(local.protected_routes) == 9 && length(local.public_routes) == 4
    error_message = "Nine routes must require the JWT authorizer and four stay public."
  }
}

run "db_ingress_only_from_db_services_and_db_init" {
  command = apply

  assert {
    condition = (
      toset([for s, m in module.service : s if length(m.database_ingress_rule_ids) > 0]) == toset(["user", "product", "order", "payment"]) &&
      alltrue([for s in ["user", "product", "order", "payment"] : keys(module.service[s].database_ingress_rule_ids) == ["rds"]]) &&
      aws_vpc_security_group_ingress_rule.db_from_db_init.security_group_id == module.rds.security_group_id &&
      aws_vpc_security_group_ingress_rule.db_from_db_init.cidr_ipv4 == null &&
      aws_vpc_security_group_ingress_rule.db_from_db_init.from_port == 5432 &&
      aws_vpc_security_group_ingress_rule.db_from_db_init.to_port == 5432 &&
      aws_vpc_security_group_ingress_rule.db_from_db_init.referenced_security_group_id == module.db_init.security_group_id
    )
    error_message = "The RDS SG may accept 5432 only from the four DB services' SGs and db-init's SG, never from a CIDR."
  }
}

run "every_queue_has_dlq" {
  command = apply

  assert {
    condition = (
      toset(keys(module.messaging.queue_arns)) == toset(["payment", "order", "notification"]) &&
      toset(keys(module.messaging.dlq_arns)) == toset(keys(module.messaging.queue_arns))
    )
    error_message = "Every consumer queue must have its own DLQ."
  }
}

run "waf_attached_to_distribution" {
  command = apply

  assert {
    condition     = module.waf.web_acl_arn == "arn:aws:wafv2:us-east-1:111111111111:global/webacl/lesson14-dev/0123abcd-0123-abcd-0123-0123456789ab"
    error_message = "The web ACL must be created through the us-east-1 provider."
  }
  assert {
    condition     = module.edge.web_acl_id == module.waf.web_acl_arn
    error_message = "The CloudFront distribution must use the WAF web ACL."
  }
  assert {
    condition = (
      toset(keys(module.edge.bucket_public_access_blocks)) == toset(["storefront", "images"]) &&
      alltrue([for b in values(module.edge.bucket_public_access_blocks) :
      b.block_public_acls && b.block_public_policy && b.ignore_public_acls && b.restrict_public_buckets])
    )
    error_message = "Both CloudFront buckets (storefront and images) must block all public access."
  }
}

run "ses_identity_optional" {
  command = apply
  # The null default (log mode, no identity) is asserted in six_services_and_db_init.
  variables {
    notify_from_email = "shop@example.com"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender) == 1 && aws_sesv2_email_identity.sender[0].email_identity == "shop@example.com"
    error_message = "notify_from_email must create the SES sender identity."
  }
  assert {
    condition = (
      local.service_environment["notification"].NOTIFY_MODE == "ses" &&
      local.service_environment["notification"].NOTIFY_FROM == "shop@example.com" &&
      contains(flatten([for s in jsondecode(local.task_policies["notification"]).Statement : s.Action]), "ses:SendEmail")
    )
    error_message = "With a sender, notification must send through SES and may call ses:SendEmail."
  }
}

run "pii_masked_in_every_log_group" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_cloudwatch_log_data_protection_policy.this)) == toset(["user", "product", "cart", "order", "payment", "notification", "db-init", "api-access"]) &&
      alltrue([for p in aws_cloudwatch_log_data_protection_policy.this :
        jsondecode(p.policy_document).Statement[0].DataIdentifier == jsondecode(p.policy_document).Statement[1].DataIdentifier &&
        contains(jsondecode(p.policy_document).Statement[1].DataIdentifier, "arn:aws:dataprotection::aws:data-identifier/EmailAddress") &&
        contains(jsondecode(p.policy_document).Statement[1].DataIdentifier, "arn:aws:dataprotection::aws:data-identifier/IpAddress") &&
      jsondecode(p.policy_document).Statement[1].Operation == { Deidentify = { MaskConfig = {} } }])
    )
    error_message = "Every service, db-init and API access log group must mask emails and IP addresses."
  }
}

run "reject_bad_project" {
  command = plan
  variables {
    project = "Lesson_14"
  }
  expect_failures = [var.project]
}
