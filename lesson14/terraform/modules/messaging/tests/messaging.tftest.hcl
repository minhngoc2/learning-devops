# Mocked AWS: no credentials or real resources.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:ap-southeast-1:111111111111:lesson14-dev-order-events"
    }
  }
}

variables {
  name = "lesson14-dev"
  consumers = {
    payment      = ["OrderCreated"]
    order        = ["PaymentSucceeded", "PaymentFailed"]
    notification = ["OrderCreated", "PaymentSucceeded", "PaymentFailed"]
  }
}

run "queue_and_dlq_per_consumer" {
  command = apply # queue ARNs are only known after (mocked) apply

  assert {
    condition = (
      aws_sns_topic.this.name == "lesson14-dev-order-events" &&
      length(aws_sqs_queue.this) == 3 && length(aws_sqs_queue.dlq) == 3 &&
      alltrue([for c in keys(var.consumers) : aws_sqs_queue.this[c].name == "lesson14-dev-${c}-order-events" && aws_sqs_queue.dlq[c].name == "lesson14-dev-${c}-order-events-dlq"])
    )
    error_message = "Each consumer needs one queue and one DLQ named lesson14-dev-<consumer>-order-events[-dlq]."
  }
  assert {
    condition = alltrue([
      for c in keys(var.consumers) :
      jsondecode(aws_sqs_queue.this[c].redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq[c].arn &&
      jsondecode(aws_sqs_queue.this[c].redrive_policy).maxReceiveCount == 5
    ])
    error_message = "Every queue must redrive to its own DLQ after 5 receives."
  }
  assert {
    condition = alltrue([
      for c in keys(var.consumers) :
      aws_sqs_queue.this[c].receive_wait_time_seconds == 20 && aws_sqs_queue.this[c].sqs_managed_sse_enabled && aws_sqs_queue.dlq[c].sqs_managed_sse_enabled &&
      jsondecode(aws_sqs_queue_policy.this[c].policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == aws_sns_topic.this.arn
    ])
    error_message = "Queues must long-poll, be encrypted, and accept messages only from the topic."
  }
  assert {
    condition     = tolist(keys(output.queue_urls)) == tolist(sort(keys(var.consumers))) && output.queue_arns["payment"] == aws_sqs_queue.this["payment"].arn && output.dlq_names["order"] == "lesson14-dev-order-order-events-dlq"
    error_message = "Outputs must be maps keyed by consumer."
  }
}

run "filter_policies_match_consumers" {
  command = plan

  assert {
    condition     = jsondecode(aws_sns_topic_subscription.this["payment"].filter_policy).event_type == ["OrderCreated"]
    error_message = "The payment queue must receive only OrderCreated."
  }
  assert {
    condition = alltrue([
      for c, types in var.consumers :
      tolist(jsondecode(aws_sns_topic_subscription.this[c].filter_policy).event_type) == types &&
      aws_sns_topic_subscription.this[c].filter_policy_scope == "MessageAttributes"
    ])
    error_message = "Each subscription must filter the event_type message attribute to the consumer's list."
  }
}

run "raw_delivery_enabled" {
  command = plan

  assert {
    condition = alltrue([
      for c in keys(var.consumers) :
      aws_sns_topic_subscription.this[c].protocol == "sqs" && aws_sns_topic_subscription.this[c].raw_message_delivery
    ])
    error_message = "SQS subscriptions must use raw message delivery."
  }
}

run "reject_unknown_event_type" {
  command = plan
  variables {
    consumers = {
      shipping = ["OrderShipped"]
    }
  }
  expect_failures = [var.consumers]
}
