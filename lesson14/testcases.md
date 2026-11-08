# Test cases: scenarios on the live stack

These cases check the deployed stack against the assignment's scenarios: the order flow, failures, abuse, a release and personal data in logs. Run them after the [quickstart](quickstart.md) has deployed, published, seeded and verified the stack (steps 5–9), and before [cleanup](quickstart.md#12-cleanup).

Every case has the same parts:

- **Requirement:** what the design promises.
- **Steps:** the commands to run.
- **Expected:** what you should see, including which alarm should (or should not) change state.
- **Restore:** how to undo anything the case broke.
- **Result:** the outcome of the last live run, with its evidence.

## Summary

| ID | Scenario | Requirement it proves | Changes the stack? | Result |
| --- | --- | --- | --- | --- |
| [TC-01](#tc-01-place-an-order-happy-path) | Place an order | The order flow works end to end | No | **Pass** (2026-11-08) |
| [TC-02](#tc-02-payment-is-declined) | Payment is declined | A failed payment is a normal outcome, not an error | No | Not run yet |
| [TC-03](#tc-03-email-is-down) | Email is down | A failing consumer never blocks checkout | Pauses `notification` | Not run yet |
| [TC-04](#tc-04-one-service-is-down) | One service is down | Failures stay inside one service | Pauses `product` | Not run yet |
| [TC-05](#tc-05-direct-execute-api-call-is-refused) | Bypass CloudFront | The API is reachable only through CloudFront and WAF | No | **Pass** (2026-11-08) |
| [TC-06](#tc-06-spoofed-identity-headers-are-stripped) | Spoofed identity headers | Clients cannot pretend to be another customer | No | **Pass** (2026-11-08) |
| [TC-07](#tc-07-waf-rate-limit) | Request flood | WAF blocks one IP that sends too many requests | Blocks your IP for minutes | Not run yet |
| [TC-08](#tc-08-personal-data-is-masked-in-logs) | Personal data in logs | Emails, IPs and customer IDs are masked in CloudWatch | No | **Pass** (2026-11-08) |
| [TC-09](#tc-09-release-v2-with-little-downtime) | Release `v2` | Rolling release with automatic rollback | Deploys a new image | Not run yet |
| [TC-10](#tc-10-database-fails-in-one-az-design-review) | Database fails in one AZ | What survives an AZ failure | No (design review) | Explained |
| [TC-11](#tc-11-10-traffic-on-sale-day-design-review) | 10× traffic | Where the stack absorbs a spike | No (design review) | Explained |

## Before you start

Run everything from `lesson14/`, in one terminal. These are the same variables as [quickstart step 9.1](quickstart.md#9-verify); set them again in a new terminal:

```sh
export AWS_PAGER=""
export AWS_REGION=ap-southeast-1
tf() { terraform -chdir=terraform/environments/dev "$@"; }
EMAIL='you@example.com'            # the demo customer from quickstart step 8
PASSWORD='Demo-Passw0rd!'
CF_URL="$(tf output -raw cloudfront_url)"
CLUSTER="$(tf output -raw cluster_name)"
TOKEN="$(curl -s -X POST "$CF_URL/api/users/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')" | jq -r .id_token)"
AUTH="Authorization: Bearer $TOKEN"
```

The token lasts 60 minutes. If a call returns `401`, run the `TOKEN=` and `AUTH=` lines again.

Alarms notify the ops topic, so with `alarm_email` set you also get an email on `ALARM` and on `OK`. To read one alarm's state:

```sh
aws cloudwatch describe-alarms --alarm-names lesson14-dev-notification-under-desired \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
```

Autoscaling owns each service's task count (min 1, max 4). To pause a service, lower the scalable target's minimum to 0 **and** set the desired count to 0. TC-03 and TC-04 do this with two helpers; define them once:

```sh
pause_service() {
  aws application-autoscaling register-scalable-target --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$1" \
    --min-capacity 0 --max-capacity 4
  aws ecs update-service --cluster "$CLUSTER" --service "$1" --desired-count 0 --query 'service.desiredCount'
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$1"
}
resume_service() {
  aws application-autoscaling register-scalable-target --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$1" \
    --min-capacity 1 --max-capacity 4
  aws ecs update-service --cluster "$CLUSTER" --service "$1" --desired-count 1 --query 'service.desiredCount'
  aws ecs wait services-stable --cluster "$CLUSTER" --services "$1"
}
```

Always resume a paused service before the next case. Terraform's settings are min 1, max 4.

## TC-01: Place an order (happy path)

**Requirement:** a customer can browse, add to the cart and check out. The order turns `PAID` and the customer gets two emails.

**Steps:** in the browser, open `$CF_URL`, log in, add two products, check out and wait on the order page. Or with curl:

```sh
curl -s -X DELETE -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart" -H "$AUTH"     # 204
curl -s -X PUT "$CF_URL/api/cart/items/p-0001" -H "$AUTH" -H 'Content-Type: application/json' -d '{"quantity":1}' | jq
curl -s -X PUT "$CF_URL/api/cart/items/p-0002" -H "$AUTH" -H 'Content-Type: application/json' -d '{"quantity":1}' | jq
ORDER_ID="$(curl -s -X POST "$CF_URL/api/orders" -H "$AUTH" | jq -r .id)"; echo "$ORDER_ID"
sleep 3
curl -s "$CF_URL/api/orders/$ORDER_ID" -H "$AUTH" | jq -r .status                     # PAID
curl -s "$CF_URL/api/payments/$ORDER_ID" -H "$AUTH" | jq '{status,amount_cents}'
```

**Expected:** `POST /api/orders` returns `201` with status `PENDING_PAYMENT`. Within a few seconds the order is `PAID` and the payment is `SUCCEEDED`. The inbox gets *Order … received* and *Order … paid*. No alarm changes state.

To trace the order through all services, open **CloudWatch → Logs Insights**, select `/ecs/lesson14-dev-order`, `/ecs/lesson14-dev-payment` and `/ecs/lesson14-dev-notification`, and run:

```text
fields @timestamp, @log, msg, order_id, status, event_type
| filter order_id = "<ORDER_ID>"
| sort @timestamp asc
```

**Result: Pass (2026-11-08).** Order `ord-b76113cc` (Cà phê Buôn Ma Thuột 500g + Phin pha cà phê, 250.000 ₫) took 0.4 s from checkout to both emails:

| Time (UTC+7) | Service | Log message |
| --- | --- | --- |
| 13:59:08.96 | order | `order created`, `total_cents` 25000000 |
| 13:59:09.05 | payment | `payment recorded`, `pay-0fcb9c10`, `SUCCEEDED` |
| 13:59:09.10 | order | `order status updated`, `PAID` |
| 13:59:09.16 | notification | `notification sent`, `OrderCreated` |
| 13:59:09.34 | notification | `notification sent`, `PaymentSucceeded` |

Screenshots: [README, live deployment](README.md#6-live-deployment-evidence).

## TC-02: Payment is declined

**Requirement:** a declined card ends the order as `PAYMENT_FAILED`, tells the customer, and is not treated as a system error.

**Steps:** product `p-0005` costs 9,999,999 cents. Ordered alone, the total ends in `99`, and the demo payment rule declines it:

```sh
curl -s -X DELETE -o /dev/null "$CF_URL/api/cart" -H "$AUTH"
curl -s -X PUT "$CF_URL/api/cart/items/p-0005" -H "$AUTH" -H 'Content-Type: application/json' -d '{"quantity":1}' | jq
ORDER_ID="$(curl -s -X POST "$CF_URL/api/orders" -H "$AUTH" | jq -r .id)"; echo "$ORDER_ID"
sleep 5
curl -s "$CF_URL/api/orders/$ORDER_ID" -H "$AUTH" | jq -r .status          # PAYMENT_FAILED
curl -s "$CF_URL/api/payments/$ORDER_ID" -H "$AUTH" | jq '{status,reason}'
```

**Expected:** the payment shows `"status": "FAILED"` and `"reason": "card declined (demo rule: totals ending in 99)"`. The order page offers **Add these items to your cart again**. Notification sends *Payment for order <id> failed: …*. No alarm fires: every service handled the event successfully.

**Result:** not run yet.

## TC-03: Email is down

**Requirement:** when the email worker is down, orders still complete. Its messages wait in its own queue and are sent when it returns.

**Steps:** pause the Notification worker, then place an order as in TC-01:

```sh
pause_service lesson14-dev-notification
```

Watch its queue grow. Each order adds two messages (`OrderCreated` and `PaymentSucceeded`):

```sh
Q_URL="$(aws sqs get-queue-url --queue-name lesson14-dev-notification-order-events --query QueueUrl --output text)"
DLQ_URL="$(aws sqs get-queue-url --queue-name lesson14-dev-notification-order-events-dlq --query QueueUrl --output text)"
aws sqs get-queue-attributes --queue-url "$Q_URL" --attribute-names ApproximateNumberOfMessages
```

**Expected:**

- The order still becomes `PAID`: Payment and Order don't depend on Notification.
- `ApproximateNumberOfMessages` grows by 2 per order.
- After about 5 minutes with no running task, `lesson14-dev-notification-under-desired` goes to `ALARM`. It treats missing `RunningTaskCount` data as breaching, because Container Insights stops reporting a service that has no tasks. (TODO: confirm the timing in a live run.)

**Restore:** resume the worker and watch the waiting emails go out:

```sh
resume_service lesson14-dev-notification
aws logs tail /ecs/lesson14-dev-notification --since 5m --format short
aws sqs get-queue-attributes --queue-url "$Q_URL" --attribute-names ApproximateNumberOfMessages     # 0
aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names ApproximateNumberOfMessages   # 0
```

The queue drains to `0` and the emails arrive. The DLQ stays at `0`, because the messages were waiting, not failing. A message goes to the DLQ only after 5 failed receives, for example when SES rejects every send; then `lesson14-dev-notification-dlq-not-empty` fires within a minute. `lesson14-dev-notification-under-desired` returns to `OK`.

**Result:** not run yet.

## TC-04: One service is down

**Requirement:** when one service fails, only its own paths fail. The rest of the shop keeps working.

**Steps:**

```sh
pause_service lesson14-dev-product
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"                 # 503: no healthy target
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/orders" -H "$AUTH"         # 200
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart" -H "$AUTH"           # 200
```

**Expected:** the product routes return `503`, while orders and cart return `200`. In the browser, `/` loads but shows an error instead of the products, and `/orders` still lists your orders. Checkout fails, because Order reads the prices from Product at checkout. `lesson14-dev-product-under-desired` goes to `ALARM` after about 5 minutes. If you keep calling the product routes, `lesson14-dev-apigw-5xx-rate` can fire too (more than 1 % `5xx` for 5 minutes). The ALB 5xx alarm counts only errors returned by targets, so an empty target group does not trigger it.

**Restore:**

```sh
resume_service lesson14-dev-product
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"                 # 200
```

**Result:** not run yet.

## TC-05: Direct execute-api call is refused

**Requirement:** the API is reachable only through CloudFront, so every request passes WAF.

**Steps:** call API Gateway's own URL, which skips CloudFront and so lacks the secret `X-Origin-Verify` header:

```sh
curl -i "$(tf output -raw api_endpoint)/api/products"              # 403 {"error":"forbidden"}
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"    # 200
```

**Expected:** the direct call returns `403`, and the same path through CloudFront returns `200`. API Gateway's access log (`/aws/apigateway/lesson14-dev`) records the `403`. No alarm fires, because the 5xx alarms ignore `4xx`.

**Result: Pass (2026-11-08).** `scripts/check-release.sh v1` makes both calls and printed `All 6 services run v1; CloudFront serves the API; direct execute-api is refused.`

## TC-06: Spoofed identity headers are stripped

**Requirement:** services trust `X-Customer-Sub` and `X-Customer-Email` because only API Gateway sets them. A client must not be able to send its own.

**Steps:** send a public request with a made-up `X-Customer-Sub`, then look for it in the service log:

```sh
MARK="spoof-$(date +%s)"
curl -s -o /dev/null -w '%{http_code}\n' -H "X-Customer-Sub: $MARK" "$CF_URL/api/products"   # 200
sleep 20
aws logs filter-log-events --log-group-name /ecs/lesson14-dev-product \
  --start-time $((($(date +%s) - 120) * 1000)) --filter-pattern "\"$MARK\"" --query 'length(events)'
```

**Expected:** the request succeeds, the product service logs no `customer_sub` for it, and the search finds `0` events. On protected routes, API Gateway overwrites both headers from the token's claims.

**Result: Pass (2026-11-08).** The marker was found in `0` log events. Before the fix in `terraform/modules/api-gateway/main.tf` (removal values `"''"` instead of `""`), AWS stored no removal at all and spoofed headers reached the services.

## TC-07: WAF rate limit

**Requirement:** WAF blocks a single IP that sends more than 2,000 requests in 5 minutes.

> [!WARNING]
> This blocks **your IP from the whole site** (storefront and API) for several minutes, until your rate falls below the limit. Run it last, after the other cases. It costs a fraction of a cent (WAF, CloudFront and S3 requests). WAF can take a minute or two to start blocking after you pass the limit.

**Steps:** send about 3,000 requests to the storefront. With [`hey`](https://github.com/rakyll/hey):

```sh
hey -n 3000 -c 20 "$CF_URL/"
```

Without it (one request at a time, so it takes several minutes):

```sh
for i in $(seq 1 3000); do curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/"; done | sort | uniq -c
```

**Expected:** `200` at first, then `403`. The dashboard's **WAF blocked requests** widget (Edge row) shows the blocks. With `alarm_email` set, `lesson14-dev-waf-blocked-requests` goes to `ALARM` when more than 100 requests are blocked in 5 minutes. That alarm lives in us-east-1, with the web ACL:

```sh
aws cloudwatch describe-alarms --region us-east-1 --alarm-names lesson14-dev-waf-blocked-requests \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
```

**Restore:** wait. Repeat this until it prints `200` again:

```sh
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/"
```

**Result:** not run yet.

## TC-08: Personal data is masked in logs

**Requirement:** anyone reading the logs sees no customer emails, client IP addresses or customer IDs. Admins with `logs:Unmask` can still reveal them when they investigate.

`terraform/environments/dev/log-protection.tf` attaches a CloudWatch Logs data protection policy to all eight log groups (six services, `db-init`, API access). It masks AWS's managed `EmailAddress` and `IpAddress` identifiers and a custom `CustomerSub` pattern. Only log events ingested after the policy exists are masked.

**Steps:** make one logged-in and one public request, then read the newest lines back, first as a normal reader and then unmasked:

```sh
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart" -H "$AUTH"
sleep 25
START=$((($(date +%s) - 60) * 1000))
aws logs filter-log-events --log-group-name /ecs/lesson14-dev-cart --start-time "$START" --query 'events[-1].message' --output text
aws logs filter-log-events --log-group-name /aws/apigateway/lesson14-dev --start-time "$START" --query 'events[-1].message' --output text
aws logs filter-log-events --log-group-name /aws/apigateway/lesson14-dev --start-time "$START" --unmask --query 'events[-1].message' --output text
```

In the console, open a log group: masked values show as `*****`, and **Display → Temporarily unmask protected data** reveals them for readers with `logs:Unmask`.

**Expected:** `customer_sub` and `sourceIp` are masked in the normal view and readable with `--unmask`.

**Result: Pass (2026-11-08).**

| Log group | Normal view | With `--unmask` |
| --- | --- | --- |
| `/ecs/lesson14-dev-cart` | `"service":"cart","*****…*****","method":"GET"` | `"customer_sub":"<the Cognito sub>"` |
| `/aws/apigateway/lesson14-dev` | `"sourceIp":"**************"` | `"sourceIp":"<your public IP>"` |
| `/ecs/lesson14-dev-notification` (test event) | `"to":"*****************"` | `"to":"alice@example.com"` |

The custom identifier matches the key and the value together, so the whole `"customer_sub":"…"` pair is masked, while `request_id` and `event_id` (also UUIDs) stay readable for tracing.

## TC-09: Release v2 with little downtime

**Requirement:** a release replaces tasks one at a time, and a broken release rolls back on its own.

Image tags are immutable: a release pushes a new tag and points the stack at it. ECS starts the new tasks before stopping the old ones (minimum 100 %, maximum 200 % of the desired count), and the circuit breaker rolls back to the last working deployment if the new tasks fail their health checks.

**Steps:**

1. Optionally change something in `app/` (then run `go -C app test ./...`). Build and push `v2`:

   ```sh
   bash scripts/build-push.sh v2
   ```

2. Set `image_tag = "v2"` in `terraform/environments/dev/dev.tfvars`, then plan, apply and check the rollout:

   ```sh
   tf plan -var-file=dev.tfvars -out=dev.tfplan
   tf apply dev.tfplan
   bash scripts/check-release.sh v2
   ```

3. Storefront changes don't need Terraform. Generate and upload again, then invalidate the CloudFront cache so viewers get the new files:

   ```sh
   pnpm --dir storefront generate
   aws s3 sync storefront/.output/public "s3://$(tf output -raw storefront_bucket_name)/" --delete
   aws cloudfront create-invalidation --distribution-id "$(tf output -raw cloudfront_distribution_id)" --paths "/*"
   ```

**Expected:** the plan replaces the task definitions (new image tag), replaces `terraform_data.db_init` (so `db-init` runs the new image before the services roll), and updates the services that use them (TODO: fill in the counts from a live run). Keep the site open during the apply: it keeps answering. `check-release.sh` fails if any service is not stable, its primary deployment is not `COMPLETED`, or its image is not `:v2`, which is what you see after a rollback.

**Result:** not run yet.

## TC-10: Database fails in one AZ (design review)

There is no live test: you cannot fail an AWS availability zone on demand. This is what the design does.

The dev stack runs one RDS instance in one AZ (`multi_az = false`) to keep costs down, so an AZ failure would stop `user`, `product`, `order` and `payment` until the instance recovers. Cart keeps working, because DynamoDB already stores data across AZs, and the ECS services and the ALB already span both AZs.

For production, set `multi_az = true` in `dev.tfvars`. RDS then keeps a synchronous standby in the second AZ and fails over to it automatically, at the same DNS name. It doubles the database cost, and changing it on a running instance takes a while. With `single_nat_gateway = false`, each AZ also gets its own NAT gateway, so outbound traffic survives an AZ failure.

## TC-11: 10× traffic on sale day (design review)

There is no live test: from one machine, the WAF rate limit (TC-07) blocks you long before the services feel any load. These layers absorb a spike, from the outside in:

| Layer | What it does under load |
| --- | --- |
| CloudFront | Serves the storefront and product images from edge caches, so most page views never reach the VPC |
| WAF | Blocks single IPs above 2,000 requests per 5 minutes |
| API Gateway | Throttles the stage at 50 requests/s with bursts of 100, returning `429` instead of overloading the services |
| ECS autoscaling | Each service scales from 1 to 4 tasks to keep average CPU near 60 % |
| DynamoDB | On-demand capacity: the cart table scales without planning |
| SNS + SQS | Queues buffer events, so Payment and Notification work through a burst at their own pace |

The limit is the database: one `db.t4g.micro` instance. The `lesson14-dev-rds-cpu` and `lesson14-dev-rds-connections` alarms warn first. Raise `db_instance_class` or `max_count` in `dev.tfvars` for a real sale.

## After the tests

Make sure nothing is left paused (all six services `1/1`), then continue with [quickstart step 12: cleanup](quickstart.md#12-cleanup):

```sh
aws ecs describe-services --cluster "$CLUSTER" \
  --services lesson14-dev-{user,product,cart,order,payment,notification} \
  --query 'services[].[serviceName,runningCount,desiredCount]' --output text
```
