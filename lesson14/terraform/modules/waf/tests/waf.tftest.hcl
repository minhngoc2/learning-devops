# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name = "lesson14-dev"
}

run "cloudfront_scope_three_rules" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && length(one(aws_wafv2_web_acl.this.default_action).allow) == 1
    error_message = "The web ACL must be CLOUDFRONT scope and allow by default."
  }
  assert {
    condition = (
      length(aws_wafv2_web_acl.this.rule) == 3 &&
      toset([for r in aws_wafv2_web_acl.this.rule : r.name]) == toset(["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "rate-limit"]) &&
      toset([for r in aws_wafv2_web_acl.this.rule : r.priority]) == toset([1, 2, 3])
    )
    error_message = "The web ACL must have the two managed rule groups and the rate-limit rule at priorities 1–3."
  }
  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      one(one(r.statement).rate_based_statement).limit == 2000 &&
      one(one(r.statement).rate_based_statement).aggregate_key_type == "IP" &&
      length(one(r.action).block) == 1
      if r.name == "rate-limit"
    ])
    error_message = "The rate-limit rule must block above 2000 requests per IP (default rate_limit)."
  }
  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      one(r.visibility_config).sampled_requests_enabled && one(r.visibility_config).metric_name == "lesson14-dev-${r.name}"
    ])
    error_message = "Every rule must sample requests and use the metric name <name>-<rule>."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.blocked) == 0
    error_message = "No alarm without ops_topic_arn (the default null)."
  }
}

run "alarm_only_with_topic" {
  command = plan
  variables {
    ops_topic_arn = "arn:aws:sns:us-east-1:111111111111:lesson14-dev-ops"
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.blocked) == 1 &&
      contains(aws_cloudwatch_metric_alarm.blocked[0].alarm_actions, var.ops_topic_arn) &&
      aws_cloudwatch_metric_alarm.blocked[0].namespace == "AWS/WAFV2" &&
      aws_cloudwatch_metric_alarm.blocked[0].metric_name == "BlockedRequests" &&
      aws_cloudwatch_metric_alarm.blocked[0].dimensions == tomap({ WebACL = "lesson14-dev", Region = "us-east-1", Rule = "ALL" }) &&
      aws_cloudwatch_metric_alarm.blocked[0].threshold == 100
    )
    error_message = "With ops_topic_arn, one BlockedRequests alarm must notify the topic."
  }
}

run "reject_bad_rate_limit" {
  command = plan
  variables {
    rate_limit = 50
  }
  expect_failures = [var.rate_limit]
}
