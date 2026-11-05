locals {
  # Secret version ARNs equal the secret ARNs; referencing the versions makes tasks wait until the values exist.
  origin_verify_secret_arn = aws_secretsmanager_secret_version.origin_verify.secret_arn
  db_role_secret_arns      = { for s in local.db_services : s => aws_secretsmanager_secret_version.db_role[s].secret_arn }

  db_environment = {
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.db_name
  }

  service_db_environment = {
    for s in local.db_services : s => merge(local.db_environment, {
      DB_USER   = "svc_${s}"
      DB_SCHEMA = local.db_schemas[s]
    })
  }

  service_environment = {
    for s in local.services : s => merge(
      {
        SERVICE    = s
        PORT       = "8080"
        AWS_REGION = var.aws_region
        LOG_LEVEL  = "info"
      },
      lookup(local.service_db_environment, s, {}),
      {
        user = {
          AUTH_MODE            = "cognito"
          COGNITO_USER_POOL_ID = module.cognito.user_pool_id
          COGNITO_CLIENT_ID    = module.cognito.client_id
        }
        product = {
          IMAGES_BUCKET   = module.edge.images_bucket_name
          PUBLIC_BASE_URL = "https://${module.edge.domain_name}"
        }
        cart = {
          CART_TABLE    = module.cart_table.table_name
          CART_TTL_DAYS = "7"
        }
        order = {
          EVENT_BUS = "sns"
          TOPIC_ARN = module.messaging.topic_arn
          QUEUE_URL = module.messaging.queue_urls["order"]
          ALB_URL   = "http://${module.alb.dns_name}"
        }
        payment = {
          EVENT_BUS = "sns"
          TOPIC_ARN = module.messaging.topic_arn
          QUEUE_URL = module.messaging.queue_urls["payment"]
        }
        notification = merge(
          {
            EVENT_BUS   = "sns"
            QUEUE_URL   = module.messaging.queue_urls["notification"]
            NOTIFY_MODE = var.notify_from_email == null ? "log" : "ses"
          },
          var.notify_from_email == null ? {} : { NOTIFY_FROM = var.notify_from_email },
        )
      }[s],
    )
  }

  service_secrets = {
    for s in local.services : s => merge(
      contains(local.db_services, s) ? { DB_PASSWORD = local.db_role_secret_arns[s] } : {},
      s == "order" ? { ORIGIN_VERIFY = local.origin_verify_secret_arn } : {},
    )
  }

  consume_actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]

  # What each app may call itself (its task role); ECR/logs/secrets belong to the execution role in the module.
  task_policies = {
    user = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "CognitoUsers"
        Effect   = "Allow"
        Action   = ["cognito-idp:SignUp", "cognito-idp:AdminConfirmSignUp", "cognito-idp:AdminUpdateUserAttributes", "cognito-idp:InitiateAuth", "cognito-idp:AdminGetUser"]
        Resource = module.cognito.user_pool_arn
      }]
    })
    product = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "ProductImages"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${module.edge.images_bucket_arn}/products/*"
      }]
    })
    cart = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "CartTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = module.cart_table.table_arn
      }]
    })
    order = jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Sid = "PublishEvents", Effect = "Allow", Action = "sns:Publish", Resource = module.messaging.topic_arn },
        { Sid = "ConsumeQueue", Effect = "Allow", Action = local.consume_actions, Resource = module.messaging.queue_arns["order"] },
      ]
    })
    payment = jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Sid = "PublishEvents", Effect = "Allow", Action = "sns:Publish", Resource = module.messaging.topic_arn },
        { Sid = "ConsumeQueue", Effect = "Allow", Action = local.consume_actions, Resource = module.messaging.queue_arns["payment"] },
      ]
    })
    notification = jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{ Sid = "ConsumeQueue", Effect = "Allow", Action = local.consume_actions, Resource = module.messaging.queue_arns["notification"] }],
        [for identity in aws_sesv2_email_identity.sender : { Sid = "SendEmail", Effect = "Allow", Action = "ses:SendEmail", Resource = identity.arn }],
      )
    })
  }

  # Web services sit behind the ALB; notification is a pure queue worker.
  service_target_groups = { for s in keys(local.web_services) : s => module.alb.target_group_arns[s] }
}

module "service" {
  source   = "../../modules/ecs-service"
  for_each = local.services

  name             = "${local.name}-${each.key}"
  cluster_id       = module.cluster.cluster_id
  cluster_name     = module.cluster.cluster_name
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.private_subnet_ids
  image            = "${module.ecr.repository_urls["${var.project}/${each.key}"]}:${var.image_tag}"
  desired_count    = var.desired_count
  min_count        = var.min_count
  max_count        = var.max_count
  environment      = local.service_environment[each.key]
  secrets          = local.service_secrets[each.key]
  task_policy_json = local.task_policies[each.key]
  target_group_arn = lookup(local.service_target_groups, each.key, null)
  # format() tells Terraform the still-unknown SG ID is not null, so the module's count on it is known at plan time.
  ingress_security_group_id = contains(keys(local.web_services), each.key) ? format("%s", module.alb.security_group_id) : null
  log_retention_days        = var.log_retention_days
}

# One-off task (no service): creates schemas, svc_* roles and grants with the RDS master password. Run it with
# the db_init_run_command output after the first apply and after adding a service.
module "db_init" {
  source = "../../modules/ecs-service"

  name               = "${local.name}-db-init"
  create_service     = false
  cluster_id         = module.cluster.cluster_id
  cluster_name       = module.cluster.cluster_name
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  image              = "${module.ecr.repository_urls["${var.project}/db-init"]}:${var.image_tag}"
  log_retention_days = var.log_retention_days

  environment = merge(local.db_environment, {
    SERVICE       = "db-init"
    AWS_REGION    = var.aws_region
    LOG_LEVEL     = "info"
    DB_ADMIN_USER = module.rds.username
  })
  secrets = merge(
    { DB_ADMIN_PASSWORD = "${module.rds.secret_arn}:password::" },
    { for s in local.db_services : "ROLE_PASSWORD_${upper(s)}" => local.db_role_secret_arns[s] },
  )
}
