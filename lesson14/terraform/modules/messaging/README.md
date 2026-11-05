# Order events messaging

One SNS topic `<name>-order-events` fanned out to one SQS queue per consumer. Each subscription uses **raw delivery** and a filter policy on the `event_type` **message attribute**, so a consumer only receives the event types it lists. Each queue long-polls, is encrypted (SQS-managed SSE), accepts messages only from the topic, and moves a message to its own DLQ (`-dlq`, kept 14 days) after `max_receive_count` failed receives.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | Prefix: 1–40 letters/digits/`-`/`_` |
| `event_types` | `["OrderCreated", "PaymentSucceeded", "PaymentFailed"]` | Allowed `event_type` values; non-empty, no duplicates |
| `consumers` | Required | Map consumer → event types; names lowercase (≤ 20), each list non-empty and ⊆ `event_types` |
| `max_receive_count` | `5` | Receives before the DLQ (1–1000) |
| `visibility_timeout_seconds` | `30` | 0–43200; above the handler's processing time |
| `message_retention_seconds` | `345600` | Queue retention, 60–1209600 (4 days default) |

| Output | Use |
| --- | --- |
| `topic_arn` | Publisher `TOPIC_ARN`, `sns:Publish` policy |
| `queue_urls` | Map consumer → URL: consumer `QUEUE_URL` |
| `queue_arns` | Map consumer → ARN: `sqs:ReceiveMessage` / `DeleteMessage` policies |
| `queue_names`, `dlq_names` | CloudWatch alarm dimensions |
| `dlq_arns` | Redrive tooling |

```hcl
module "messaging" {
  source = "../../modules/messaging"
  name   = "lesson14-dev"
  consumers = {
    payment      = ["OrderCreated"]
    order        = ["PaymentSucceeded", "PaymentFailed"]
    notification = ["OrderCreated", "PaymentSucceeded", "PaymentFailed"]
  }
}
```

Tests: [`tests/messaging.tftest.hcl`](tests/messaging.tftest.hcl).
