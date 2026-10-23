# Lambda function

Reusable, language-agnostic module: an execution role that only Lambda can assume (with `AWSLambdaBasicExecutionRole` for logs), a `/aws/lambda/<name>` log group with retention, and the function from a prebuilt `.zip`. The caller builds and zips the code.

| Input | Default | Purpose |
| --- | --- | --- |
| `function_name` | Required | Names the function, role (`<name>-lambda`) and log group; 1–57 chars so the role name fits IAM's 64 |
| `package_path` | Required | Deployment `.zip`; its hash triggers code updates |
| `runtime` | Required | e.g. `provided.al2023` (Go), `python3.13`, `nodejs22.x` |
| `handler` | Required | `bootstrap` for `provided.*`; `module.func` for managed runtimes |
| `architectures` | `["arm64"]` | Must match how the package was built |
| `memory_size` | `128` | MB (128–10240); CPU scales with memory |
| `timeout` | `10` | Seconds per invocation (1–900; HTTP API waits at most 30) |
| `environment_variables` | `{}` | Plain config, not secrets |
| `reserved_concurrent_executions` | `-1` | `-1` = unreserved; a number caps simultaneous runs |
| `log_retention_days` | `7` | Log retention; must be a CloudWatch value (0 = never expire, or 1, 3, 5, 7, 14, 30, …) |

Outputs: `function_name`, `function_arn`, `invoke_arn`, `role_name`, `log_group_name`.

Need AWS API access from the code? Attach a policy to `role_name` in the caller. Example use: the [dev root](../../environments/dev/main.tf).
