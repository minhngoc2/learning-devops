# Lambda function

Reusable, language-agnostic module. It creates:

- an execution role that only Lambda can assume, with `AWSLambdaBasicExecutionRole` for logs;
- optional least-privilege inline policies passed in by the caller;
- a `/aws/lambda/<name>` log group with retention;
- the function, from a prebuilt `.zip` that the caller builds.

| Input | Default | Purpose |
| --- | --- | --- |
| `function_name` | Required | Names the function, role (`<name>-lambda`) and log group; 1–57 characters so the role name fits IAM's 64 |
| `package_path` | Required | Deployment `.zip`; a new hash triggers a code update |
| `runtime` | Required | e.g. `python3.13`, `nodejs22.x`, `provided.al2023` (Go) |
| `handler` | Required | `file.function` for managed runtimes (`handler.lambda_handler`); `bootstrap` for `provided.*` |
| `architectures` | `["arm64"]` | Must match how the package was built (pure Python works on both) |
| `memory_size` | `128` | MB (128–10240); CPU scales with memory |
| `timeout` | `10` | Seconds per invocation (1–900); an HTTP API waits at most 30 |
| `environment_variables` | `{}` | Plain configuration, not secrets |
| `inline_policies` | `{}` | `{ name = policy JSON }`; each entry becomes one role policy. Use it to grant the code AWS API access |
| `log_format` | `Text` | `JSON` makes the runtime write structured records |
| `reserved_concurrent_executions` | `-1` | `-1` = unreserved; a number caps simultaneous runs |
| `log_retention_days` | `7` | Must be a value CloudWatch accepts (0 = never expire, or 1, 3, 5, 7, 14, 30, …) |

Outputs: `function_name`, `function_arn`, `invoke_arn`, `role_name`, `log_group_name`, `memory_size`.

Example use: the [dev root](../../environments/dev/main.tf) runs Python with 1024 MB and read-only access to one DynamoDB table:

```hcl
inline_policies = {
  users-table-read = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:Scan"], Resource = module.users_table.table_arn }]
  })
}
```

Keys of `inline_policies` must be known at plan time (they are `for_each` keys); values can come from other resources.
