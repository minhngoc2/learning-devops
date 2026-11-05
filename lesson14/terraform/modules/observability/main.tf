resource "aws_sns_topic" "ops" {
  name = "${var.name}-ops"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.ops.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alb_dimensions = { LoadBalancer = var.alb_arn_suffix }
  db_dimensions  = { DBInstanceIdentifier = var.db_identifier }
  api_dimensions = { ApiId = var.api_id }

  # Every main queue is its DLQ name without the "-dlq" suffix (messaging module naming).
  queue_names = { for c, dlq in var.dlq_names : c => trimsuffix(dlq, "-dlq") }

  alarms = concat(
    [
      aws_cloudwatch_metric_alarm.alb_5xx_rate,
      aws_cloudwatch_metric_alarm.alb_p95_latency,
      aws_cloudwatch_metric_alarm.rds_cpu,
      aws_cloudwatch_metric_alarm.rds_connections,
      aws_cloudwatch_metric_alarm.apigw_5xx_rate,
    ],
    values(aws_cloudwatch_metric_alarm.dlq_not_empty),
    values(aws_cloudwatch_metric_alarm.service_under_desired),
  )
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.name}-alb-5xx-rate"
  alarm_description   = "More than 5 % of ALB requests returned a target 5xx for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  metric_query {
    id          = "rate"
    expression  = "m5xx / mreq * 100"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "m5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.alb_dimensions
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "mreq"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.alb_dimensions
      stat        = "Sum"
      period      = 60
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_p95_latency" {
  alarm_name          = "${var.name}-alb-p95-latency"
  alarm_description   = "ALB target p95 response time above 1 s for 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dimensions
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  for_each = var.dlq_names

  alarm_name          = "${var.name}-${each.key}-dlq-not-empty"
  alarm_description   = "${each.value} holds at least one message that failed processing"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "service_under_desired" {
  for_each = var.service_names

  alarm_name          = "${var.name}-${each.key}-under-desired"
  alarm_description   = "${each.value} ran fewer than ${var.desired_counts[each.key]} tasks for 5 minutes"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = each.value }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanThreshold"
  threshold           = var.desired_counts[each.key]
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu"
  alarm_description   = "RDS CPU above 80 % for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.db_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.name}-rds-connections"
  alarm_description   = "RDS connections above 80 % of max_connections (${var.db_max_connections})"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = local.db_dimensions
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = floor(var.db_max_connections * 0.8)
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]
}

resource "aws_cloudwatch_metric_alarm" "apigw_5xx_rate" {
  alarm_name          = "${var.name}-apigw-5xx-rate"
  alarm_description   = "More than 1 % of API Gateway requests returned 5xx for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1
  evaluation_periods  = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  metric_query {
    id          = "rate"
    expression  = "m5xx / mcount * 100"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "m5xx"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "5xx"
      dimensions  = local.api_dimensions
      stat        = "Sum"
      period      = 60
    }
  }

  metric_query {
    id = "mcount"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      dimensions  = local.api_dimensions
      stat        = "Sum"
      period      = 60
    }
  }
}

locals {
  # Each row: a "## " heading, then its metric widgets side by side across the 24-column grid.
  rows = [
    {
      title = "## Edge (CloudFront + WAF, us-east-1)"
      widgets = [
        { title = "CloudFront requests", region = "us-east-1", stat = "Sum", metrics = [["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global"]] },
        { title = "CloudFront 5xx error rate (%)", region = "us-east-1", stat = "Average", metrics = [["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global"]] },
        { title = "WAF blocked requests", region = "us-east-1", stat = "Sum", metrics = [["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", "us-east-1", "Rule", "ALL"]] },
      ]
    },
    {
      title = "## API (API Gateway)"
      widgets = [
        { title = "API requests", region = var.aws_region, stat = "Sum", metrics = [["AWS/ApiGateway", "Count", "ApiId", var.api_id]] },
        { title = "API 4xx", region = var.aws_region, stat = "Sum", metrics = [["AWS/ApiGateway", "4xx", "ApiId", var.api_id]] },
        { title = "API 5xx", region = var.aws_region, stat = "Sum", metrics = [["AWS/ApiGateway", "5xx", "ApiId", var.api_id]] },
        { title = "API latency p95 (ms)", region = var.aws_region, stat = "p95", metrics = [["AWS/ApiGateway", "Latency", "ApiId", var.api_id]] },
      ]
    },
    {
      title = "## Services (ECS Container Insights + ALB)"
      widgets = [
        { title = "CPU utilized", region = var.aws_region, stat = "Average", metrics = [for s in values(var.service_names) : ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.cluster_name, "ServiceName", s]] },
        { title = "Memory utilized (MiB)", region = var.aws_region, stat = "Average", metrics = [for s in values(var.service_names) : ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.cluster_name, "ServiceName", s]] },
        { title = "Running tasks", region = var.aws_region, stat = "Average", metrics = [for s in values(var.service_names) : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s]] },
        { title = "Target response time p95 (s)", region = var.aws_region, stat = "p95", metrics = [for k, tg in var.target_group_arn_suffixes : ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", tg, "LoadBalancer", var.alb_arn_suffix, { label = k }]] },
      ]
    },
    {
      title = "## Data (RDS + DynamoDB)"
      widgets = [
        { title = "RDS CPU (%)", region = var.aws_region, stat = "Average", metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier]] },
        { title = "RDS connections", region = var.aws_region, stat = "Maximum", metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier]] },
        { title = "RDS free storage (bytes)", region = var.aws_region, stat = "Minimum", metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_identifier]] },
        # Tables are found by name prefix, so the module needs no table list.
        { title = "DynamoDB consumed RCU / WCU", region = var.aws_region, stat = "Sum", metrics = [
          [{ id = "rcu", label = "", expression = "SEARCH('{AWS/DynamoDB,TableName} MetricName=\"ConsumedReadCapacityUnits\" ${var.name}', 'Sum', 300)" }],
          [{ id = "wcu", label = "", expression = "SEARCH('{AWS/DynamoDB,TableName} MetricName=\"ConsumedWriteCapacityUnits\" ${var.name}', 'Sum', 300)" }],
        ] },
      ]
    },
    {
      title = "## Queues (SQS)"
      widgets = [
        { title = "Visible messages per queue", region = var.aws_region, stat = "Maximum", metrics = [for q in values(local.queue_names) : ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", q]] },
        { title = "Visible messages per DLQ", region = var.aws_region, stat = "Maximum", metrics = [for q in values(var.dlq_names) : ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", q]] },
      ]
    },
  ]

  row_height = 7 # 1 for the heading + 6 for the graphs

  dashboard_widgets = flatten([
    for i, row in local.rows : concat(
      [{
        type       = "text"
        x          = 0
        y          = i * local.row_height
        width      = 24
        height     = 1
        properties = { markdown = row.title }
      }],
      [for j, w in row.widgets : {
        type   = "metric"
        x      = j * floor(24 / length(row.widgets))
        y      = i * local.row_height + 1
        width  = floor(24 / length(row.widgets))
        height = 6
        properties = {
          title   = w.title
          region  = w.region
          stat    = w.stat
          period  = 300
          view    = "timeSeries"
          metrics = w.metrics
        }
      }]
    )
  ])
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
