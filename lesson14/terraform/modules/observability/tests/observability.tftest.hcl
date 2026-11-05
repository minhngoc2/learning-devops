# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-1:111111111111:lesson14-dev-ops"
    }
  }
}

variables {
  name           = "lesson14-dev"
  aws_region     = "ap-southeast-1"
  alb_arn_suffix = "app/l14-dev/0123456789abcdef"
  target_group_arn_suffixes = {
    user    = "targetgroup/l14-dev-user/0000000000000001"
    product = "targetgroup/l14-dev-product/0000000000000002"
    cart    = "targetgroup/l14-dev-cart/0000000000000003"
    order   = "targetgroup/l14-dev-order/0000000000000004"
    payment = "targetgroup/l14-dev-payment/0000000000000005"
  }
  cluster_name = "lesson14-dev"
  service_names = {
    user         = "lesson14-dev-user"
    product      = "lesson14-dev-product"
    cart         = "lesson14-dev-cart"
    order        = "lesson14-dev-order"
    payment      = "lesson14-dev-payment"
    notification = "lesson14-dev-notification"
  }
  desired_counts = {
    user         = 1
    product      = 2
    cart         = 1
    order        = 1
    payment      = 1
    notification = 1
  }
  db_identifier      = "lesson14-dev"
  db_max_connections = 100
  dlq_names = {
    order        = "lesson14-dev-order-order-events-dlq"
    payment      = "lesson14-dev-payment-order-events-dlq"
    notification = "lesson14-dev-notification-order-events-dlq"
  }
  api_id          = "abc123"
  web_acl_name    = "lesson14-dev"
  distribution_id = "E2EXAMPLE"
}

run "alarm_set_complete" {
  command = plan

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.dlq_not_empty) == 3 &&
      length(aws_cloudwatch_metric_alarm.service_under_desired) == 6 &&
      length(local.alarms) == 14
    )
    error_message = "5 fixed alarms + 3 DLQ alarms + 6 service alarms = 14."
  }
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.alb_5xx_rate.threshold == 5 &&
      aws_cloudwatch_metric_alarm.alb_5xx_rate.evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.alb_5xx_rate.treat_missing_data == "notBreaching" &&
      length([for q in aws_cloudwatch_metric_alarm.alb_5xx_rate.metric_query : q if q.id == "m5xx" || q.id == "mreq"]) == 2 &&
      aws_cloudwatch_metric_alarm.alb_p95_latency.extended_statistic == "p95" &&
      aws_cloudwatch_metric_alarm.alb_p95_latency.threshold == 1 &&
      aws_cloudwatch_metric_alarm.rds_cpu.threshold == 80 &&
      aws_cloudwatch_metric_alarm.rds_cpu.period == 300 &&
      aws_cloudwatch_metric_alarm.rds_connections.threshold == 80 &&
      aws_cloudwatch_metric_alarm.apigw_5xx_rate.threshold == 1
    )
    error_message = "Fixed alarm thresholds must match the spec table."
  }
  assert {
    condition = alltrue([
      for k, a in aws_cloudwatch_metric_alarm.service_under_desired :
      a.namespace == "ECS/ContainerInsights" && a.metric_name == "RunningTaskCount" &&
      a.comparison_operator == "LessThanThreshold" && a.threshold == var.desired_counts[k] &&
      a.dimensions["ServiceName"] == var.service_names[k]
    ])
    error_message = "Each service alarm fires when RunningTaskCount drops below its desired count."
  }
  assert {
    condition = alltrue([
      for k, a in aws_cloudwatch_metric_alarm.dlq_not_empty :
      a.threshold == 1 && a.comparison_operator == "GreaterThanOrEqualToThreshold" && a.dimensions["QueueName"] == var.dlq_names[k]
    ])
    error_message = "Each DLQ alarm fires on one visible message."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription without alarm_email (the default null)."
  }
}

run "all_alarms_notify_ops_topic" {
  command = apply # the topic ARN is only known after (mocked) apply

  assert {
    condition = alltrue([
      for a in local.alarms : a.alarm_actions == toset([aws_sns_topic.ops.arn])
    ]) && aws_sns_topic.ops.name == "lesson14-dev-ops" && output.ops_topic_arn == aws_sns_topic.ops.arn
    error_message = "Every alarm must notify the ops topic."
  }
}

run "email_subscription_optional" {
  command = plan
  variables {
    alarm_email = "ops@example.com"
  }

  assert {
    condition = (
      length(aws_sns_topic_subscription.email) == 1 &&
      aws_sns_topic_subscription.email[0].protocol == "email" &&
      aws_sns_topic_subscription.email[0].endpoint == "ops@example.com"
    )
    error_message = "alarm_email must add one email subscription."
  }
}

run "dashboard_has_five_rows" {
  command = plan

  assert {
    condition = length([
      for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w
      if w.type == "text" && startswith(w.properties.markdown, "## ")
    ]) >= 5
    error_message = "The dashboard must have at least five '## ' row headings."
  }
  assert {
    condition = [
      for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w.properties.region
      if w.type == "metric" && (strcontains(jsonencode(w.properties.metrics), "AWS/CloudFront") || strcontains(jsonencode(w.properties.metrics), "AWS/WAFV2"))
    ] == ["us-east-1", "us-east-1", "us-east-1"]
    error_message = "CloudFront and WAF widgets must read us-east-1."
  }
  assert {
    condition     = aws_cloudwatch_dashboard.this.dashboard_name == "lesson14-dev" && strcontains(output.dashboard_url, "region=ap-southeast-1")
    error_message = "Dashboard is named <name>; its URL points at aws_region."
  }
}
