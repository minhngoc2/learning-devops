locals {
  # Fargate CPU/memory combinations: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html#fargate-tasks-size
  fargate_memory_for_cpu = {
    "256"   = [512, 1024, 2048]
    "512"   = range(1024, 4097, 1024)
    "1024"  = range(2048, 8193, 1024)
    "2048"  = range(4096, 16385, 1024)
    "4096"  = range(8192, 30721, 1024)
    "8192"  = range(16384, 61441, 4096)
    "16384" = range(32768, 122881, 8192)
  }

  ecs_tasks_assume_role = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# Execution role = what ECS itself uses before the app starts: pull from ECR, write logs, read secrets.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = local.ecs_tasks_assume_role
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "read_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  name  = "read-secrets"
  role  = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      # valueFrom may carry a ":json-key::" suffix; IAM wants the bare secret ARN.
      Resource = distinct([for v in values(var.secrets) : join(":", slice(split(":", v), 0, 7))])
    }]
  })
}

# Task role = what the running app may call (SQS, SNS, DynamoDB, S3...).
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = local.ecs_tasks_assume_role
}

resource "aws_iam_role_policy" "task" {
  count  = var.task_policy_json == null ? 0 : 1
  name   = "app"
  role   = aws_iam_role.task.id
  policy = var.task_policy_json
}

# ECS Exec opens its shell over the SSM message channels, which the task role must allow.
resource "aws_iam_role_policy" "execute_command" {
  count = var.enable_execute_command ? 1 : 0
  name  = "execute-command"
  role  = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

# Created even without a service: callers reference it (e.g. the DB ingress rule for db-init).
resource "aws_security_group" "this" {
  name        = var.name
  description = "ECS tasks of ${var.name}"
  vpc_id      = var.vpc_id
  tags        = { Name = var.name }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_security_group_ids

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  description                  = "Container port from ${each.key}"
}

# The rule used count before ingress_security_group_ids became a map.
moved {
  from = aws_vpc_security_group_ingress_rule.this[0]
  to   = aws_vpc_security_group_ingress_rule.this["alb"]
}

# Lives in the module, not the caller, so aws_ecs_service can depend on it: a rule the caller builds from this module's
# output can only be created after the whole module, i.e. after the steady-state wait it is needed for.
resource "aws_vpc_security_group_ingress_rule" "database" {
  for_each = var.database_security_group_ids

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.this.id
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  description                  = "Database from ${var.name}"
}

# Egress to AWS APIs (ECR, Secrets Manager, CloudWatch, SQS, SNS, DynamoDB, S3) and to RDS.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "AWS APIs and RDS"
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = var.image
    essential    = true
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment  = [for k, v in var.environment : { name = k, value = v }]
    secrets      = [for k, v in var.secrets : { name = k, valueFrom = v }]
    healthCheck = {
      command     = var.health_check_command
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])

  # A precondition, not a var.memory validation: a validation reading var.cpu is skipped whenever cpu itself is invalid.
  lifecycle {
    precondition {
      condition     = contains(lookup(local.fargate_memory_for_cpu, tostring(var.cpu), []), var.memory)
      error_message = "memory ${var.memory} is not valid for cpu ${var.cpu} on Fargate (e.g. cpu 256 allows 512, 1024 or 2048)."
    }
  }
}

resource "aws_ecs_service" "this" {
  count = var.create_service ? 1 : 0

  name                   = var.name
  cluster                = var.cluster_id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_execute_command
  wait_for_steady_state  = var.wait_for_steady_state

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.target_group_arn == null ? null : 60

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]
    content {
      target_group_arn = load_balancer.value
      container_name   = "app"
      container_port   = var.container_port
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false
  }

  # A task that keeps failing health checks rolls back to the last working task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Autoscaling owns the running count after the first apply.
  lifecycle {
    ignore_changes = [desired_count]
  }

  # Tasks that open a database connection at start-up crash until this path exists.
  depends_on = [aws_vpc_security_group_ingress_rule.database]
}

resource "aws_appautoscaling_target" "this" {
  count = var.create_service ? 1 : 0

  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_count
  max_capacity       = var.max_count
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.create_service ? 1 : 0

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target
    scale_in_cooldown  = 60
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
