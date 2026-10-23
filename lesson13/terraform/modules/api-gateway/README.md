# API Gateway HTTP API

Reusable module: an API Gateway **HTTP API** (v2) whose listed routes all proxy (`AWS_PROXY`, payload format `2.0`) to one Lambda function. Creates the `$default` auto-deploying stage with throttling and JSON access logs, and the Lambda permission that lets only this API invoke the function.

| Input | Default | Purpose |
| --- | --- | --- |
| `name` | Required | API name and `/aws/apigateway/<name>` log group |
| `lambda_function_name` | Required | Function to grant invoke permission on |
| `lambda_invoke_arn` | Required | Integration target |
| `routes` | Required | Route keys, e.g. `["GET /hello", "POST /echo"]`; others return 404 |
| `throttling_burst_limit` | `20` | Burst requests (≥ 0) |
| `throttling_rate_limit` | `10` | Requests per second (≥ 0) |
| `log_retention_days` | `7` | Access-log retention; must be a CloudWatch value (0 = never expire) |

Outputs: `api_id`, `api_endpoint`, `execution_arn`, `access_log_group_name`.

Example use: the [dev root](../../environments/dev/main.tf). See the [quickstart](../../../quickstart.md) for deployment and cleanup.
