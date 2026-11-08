# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name                       = "lesson14-dev-user"
  aws_region                 = "ap-southeast-1"
  cluster_id                 = "arn:aws:ecs:ap-southeast-1:111111111111:cluster/lesson14-dev"
  cluster_name               = "lesson14-dev"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  image                      = "111111111111.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/user:v1"
  target_group_arn           = "arn:aws:elasticloadbalancing:ap-southeast-1:111111111111:targetgroup/l14-dev-user/0123456789abcdef"
  ingress_security_group_ids = { alb = "sg-0a1b2c3d4e5f60001" }
  environment                = { PORT = "8080" }
  secrets                    = { DB_PASSWORD = "arn:aws:secretsmanager:ap-southeast-1:111111111111:secret:lesson14-dev-db-AbCdEf:password::" }
}

run "web_service_behind_alb" {
  command = plan

  assert {
    condition = (
      length(aws_ecs_service.this) == 1 &&
      one(aws_ecs_service.this[0].load_balancer).container_name == "app" &&
      one(aws_ecs_service.this[0].load_balancer).container_port == 8080 &&
      one(aws_ecs_service.this[0].load_balancer).target_group_arn == var.target_group_arn &&
      aws_ecs_service.this[0].health_check_grace_period_seconds == 60
    )
    error_message = "A web service must register container app:8080 with its target group and get a 60 s grace period."
  }
  assert {
    condition = (
      keys(aws_vpc_security_group_ingress_rule.this) == ["alb"] &&
      aws_vpc_security_group_ingress_rule.this["alb"].referenced_security_group_id == "sg-0a1b2c3d4e5f60001" &&
      aws_vpc_security_group_ingress_rule.this["alb"].from_port == 8080 &&
      aws_vpc_security_group_ingress_rule.this["alb"].to_port == 8080
    )
    error_message = "The task SG must allow the container port only from the ALB SG."
  }
  assert {
    condition = (
      aws_ecs_service.this[0].launch_type == "FARGATE" &&
      aws_ecs_service.this[0].deployment_minimum_healthy_percent == 100 &&
      aws_ecs_service.this[0].deployment_maximum_percent == 200 &&
      one(aws_ecs_service.this[0].deployment_circuit_breaker).enable &&
      one(aws_ecs_service.this[0].deployment_circuit_breaker).rollback &&
      aws_ecs_service.this[0].wait_for_steady_state
    )
    error_message = "Rolling deploys at 100/200 % with circuit-breaker rollback; apply waits for a steady state by default."
  }
  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app" &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.command == ["CMD", "/app", "-healthcheck"] &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.startPeriod == 15 &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-stream-prefix"] == "app" &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets == [{ name = "DB_PASSWORD", valueFrom = var.secrets.DB_PASSWORD }] &&
      one(aws_ecs_task_definition.this.runtime_platform).cpu_architecture == "ARM64" &&
      aws_cloudwatch_log_group.this.name == "/ecs/lesson14-dev-user"
    )
    error_message = "Task definition: container app, ARM64, healthcheck, awslogs prefix app, log group /ecs/<name>."
  }
  assert {
    condition = (
      length(aws_iam_role_policy.read_secrets) == 1 &&
      jsondecode(aws_iam_role_policy.read_secrets[0].policy).Statement[0].Resource == ["arn:aws:secretsmanager:ap-southeast-1:111111111111:secret:lesson14-dev-db-AbCdEf"]
    )
    error_message = "The execution role may read exactly the referenced secrets (bare ARN, no JSON-key suffix)."
  }
  assert {
    condition     = length(aws_iam_role_policy.task) == 0
    error_message = "No task role policy when task_policy_json is null (the default)."
  }
}

run "worker_without_alb" {
  command = plan
  variables {
    name                       = "lesson14-dev-notification"
    target_group_arn           = null
    ingress_security_group_ids = {}
    wait_for_steady_state      = false
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.this) == 0 &&
      length(aws_ecs_service.this[0].load_balancer) == 0 &&
      aws_ecs_service.this[0].health_check_grace_period_seconds == null &&
      aws_vpc_security_group_egress_rule.all.cidr_ipv4 == "0.0.0.0/0" &&
      !aws_ecs_service.this[0].wait_for_steady_state
    )
    error_message = "A worker has no ingress rule, no load balancer and no grace period, but keeps egress; wait_for_steady_state = false reaches the service."
  }
}

run "task_definition_only" {
  command = plan
  variables {
    name                       = "lesson14-dev-db-init"
    create_service             = false
    target_group_arn           = null
    ingress_security_group_ids = {}
  }

  assert {
    condition = (
      length(aws_ecs_service.this) == 0 &&
      length(aws_appautoscaling_target.this) == 0 &&
      length(aws_appautoscaling_policy.cpu) == 0 &&
      aws_ecs_task_definition.this.family == "lesson14-dev-db-init" &&
      aws_security_group.this.vpc_id == var.vpc_id &&
      output.service_name == null &&
      output.scalable_target_resource_id == null
    )
    error_message = "create_service = false keeps the task definition and SG but no service or scaling."
  }
}

run "autoscaling_bounds" {
  command = plan
  variables {
    min_count = 0
    max_count = 3
  }

  assert {
    condition = (
      aws_appautoscaling_target.this[0].min_capacity == 0 &&
      aws_appautoscaling_target.this[0].max_capacity == 3 &&
      aws_appautoscaling_target.this[0].resource_id == "service/lesson14-dev/lesson14-dev-user" &&
      aws_appautoscaling_target.this[0].scalable_dimension == "ecs:service:DesiredCount" &&
      output.scalable_target_resource_id == "service/lesson14-dev/lesson14-dev-user"
    )
    error_message = "The scalable target must cover service/<cluster>/<service> with min 0 and max 3."
  }
  assert {
    condition = (
      aws_appautoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling" &&
      one(one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).predefined_metric_specification).predefined_metric_type == "ECSServiceAverageCPUUtilization" &&
      one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).target_value == 60 &&
      one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).scale_in_cooldown == 60 &&
      one(aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration).scale_out_cooldown == 60
    )
    error_message = "Target tracking on average CPU at 60 % with 60 s cooldowns."
  }
}

run "database_ingress_from_task_sg" {
  command = plan
  variables {
    database_security_group_ids = { rds = "sg-0a1b2c3d4e5f60002" }
  }

  # The task SG ID is unknown at plan time; a fixed ID lets the assertion check the rule's source.
  override_resource {
    target          = aws_security_group.this
    values          = { id = "sg-0a1b2c3d4e5f60003" }
    override_during = plan
  }

  assert {
    condition = (
      keys(aws_vpc_security_group_ingress_rule.database) == ["rds"] &&
      aws_vpc_security_group_ingress_rule.database["rds"].security_group_id == "sg-0a1b2c3d4e5f60002" &&
      aws_vpc_security_group_ingress_rule.database["rds"].referenced_security_group_id == "sg-0a1b2c3d4e5f60003" &&
      aws_vpc_security_group_ingress_rule.database["rds"].cidr_ipv4 == null &&
      aws_vpc_security_group_ingress_rule.database["rds"].from_port == 5432 &&
      aws_vpc_security_group_ingress_rule.database["rds"].to_port == 5432
    )
    error_message = "database_security_group_ids must let only this task SG into the database SG on 5432."
  }
}

run "no_database_path_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.database) == 0
    error_message = "Without database_security_group_ids the task SG gets no database rule."
  }
}

run "task_role_policy_optional" {
  command = plan
  variables {
    task_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sqs:ReceiveMessage\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = length(aws_iam_role_policy.task) == 1 && aws_iam_role_policy.task[0].policy == var.task_policy_json
    error_message = "task_policy_json must become one inline task role policy."
  }
}

run "reject_bad_inputs" {
  command = plan
  variables {
    cpu                = 300
    memory             = 3000
    min_count          = 3
    max_count          = 2
    log_retention_days = 10
    aws_region         = "Singapore"
  }
  # 3000 MiB is no Fargate size. The cpu/memory pairing is a task-definition precondition, unreachable while cpu is invalid.
  expect_failures = [var.aws_region, var.cpu, var.memory, var.max_count, var.log_retention_days]
}
