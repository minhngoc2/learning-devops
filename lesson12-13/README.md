# Lesson 12-13: Python users API on Lambda + DynamoDB

A Python `GET /users` API on AWS Lambda (1 GB) that reads a DynamoDB table, behind an API Gateway HTTP API. Terraform deploys it, with state in S3.

![Python 3.13](https://img.shields.io/badge/Python-3.13-3776AB?logo=python&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![unittest 10/10](https://img.shields.io/badge/unittest-10%2F10-brightgreen)
![terraform test 16/16](https://img.shields.io/badge/terraform%20test-16%2F16-brightgreen)
![checkov 43/43](https://img.shields.io/badge/checkov-43%2F43-brightgreen)
![live deploy verified](https://img.shields.io/badge/live%20deploy-verified-brightgreen)

> [!NOTE]
> This lesson builds on lesson 13 and reuses its modules. It adds a `dynamodb-table` module, and gives the function least-privilege access to one table. There are no servers, no VPC, and no dependencies to package: the Lambda Python runtime already includes `boto3`.

- **[Quickstart](quickstart.md)**: step-by-step bootstrap, test, deploy, verify, release and cleanup, with the output of a live run
- **[Run log](evidence/run-log.md)**: the full live run in one place, including the issues found and how they were fixed
- Modules: [state-bucket](terraform/modules/state-bucket/README.md) · [dynamodb-table](terraform/modules/dynamodb-table/README.md) · [lambda-function](terraform/modules/lambda-function/README.md) · [api-gateway](terraform/modules/api-gateway/README.md)

## Assignment

> Deploy a Node.js or Python project that connects to DynamoDB, with the Lambda memory set to 1 GB. Write a `GET /users` API, with the Lambda environment, handler, permissions, and so on.

| Requirement | How it is met | Checked live |
| --- | --- | --- |
| Python on Lambda | `python3.13`, handler `handler.lambda_handler` ([dev root](terraform/environments/dev/main.tf)) | `get-function-configuration` |
| Connects to DynamoDB | [`app/handler.py`](app/handler.py) reads the table with `boto3` | `GET /users` returns the 5 users that `scan` counts |
| Memory 1 GB | `lambda_memory_size = 1024` | `Memory: 1024`, and `memorySizeMB: 1024` in the logs |
| `GET /users` | Plus `GET /users/{id}` and `GET /health` | 6 of 6 requests return the expected status |
| Environment | `TABLE_NAME` (from the table module output) and `LOG_LEVEL` | Both present on the function |
| Permissions | The role can run `GetItem`/`Scan` on this one table. Only this API can invoke the function | Role policy and function policy read back from AWS |

## Architecture

**Client → API Gateway (HTTP API) → Lambda (Python, 1 GB) → DynamoDB**

![Lesson 12-13 architecture: inside AWS ap-southeast-1, the client calls API Gateway, which invokes the Lambda function, which reads the DynamoDB users table; a Lambda permission limits invokes to this API, and the execution role allows reading only this table; both log groups record each request. Below, the developer laptop zips handler.py, the Terraform dev root applies 19 resources and keeps state in the S3 bucket that the bootstrap root creates once](diagrams/architecture.png)

| Part | Notes |
| --- | --- |
| API Gateway | Throttled to 10 req/s (burst 20), JSON access logs. Routes that are not listed return `404` and never invoke Lambda |
| Lambda | Routes on `routeKey`. Creates the DynamoDB client once and reuses it on warm calls. Logs are JSON |
| DynamoDB | On-demand, keyed on `id`, with PITR and encryption. Seeded with 5 users from [`seed/users.json`](terraform/environments/dev/seed/users.json) |
| IAM | The Lambda permission lets only this API invoke the function. The execution role can write logs and read this one table |
| State | A private, versioned, HTTPS-only S3 bucket from `terraform/bootstrap`, with S3-native locking |

Diagram source: [`diagrams/source/architecture.json`](diagrams/source/architecture.json) (Archify).

## Layout

```text
app/                         handler.py + test_handler.py (fake table, no AWS)
terraform/bootstrap/         S3 state bucket (local state, run once)
terraform/environments/dev/  The stack: 19 resources, seed data, mocked tests
terraform/modules/           state-bucket · dynamodb-table · lambda-function · api-gateway
diagrams/                    Architecture image and its Archify source
evidence/                    Run log of the live deploy
```

## API

| Request | Status | Body |
| --- | --- | --- |
| `GET /health` | `200` | `{"status":"ok"}`, without calling DynamoDB |
| `GET /users` | `200` | `{"users":[…],"count":5}` |
| `GET /users?limit=2[&next=<cursor>]` | `200` | One page. `next` is present while more pages remain |
| `GET /users/u002` | `200` | `{"id":"u002","name":"Binh Tran",…}` |
| `GET /users/u999` | `404` | `{"error":"user not found"}` |
| `limit` outside 1–100, or a bad cursor | `400` | `{"error":"limit must be an integer between 1 and 100"}` |
| DynamoDB or code error | `500` | `{"error":"internal error"}`. The details go to the logs only |
| Any other route | `404` | `{"message":"Not Found"}` from API Gateway |

## Results

These come from a full live run in `ap-southeast-1` on 2026-10-27. The [quickstart](quickstart.md) shows the output for each step.

| Stage | Result |
| --- | --- |
| Offline checks | 10 unit tests, `fmt`, `validate`, TFLint clean. `terraform test` 16/16. Checkov 43 passed, 0 failed |
| Deploy | `19 added` in about 20 s |
| API | 6 of 6 expected statuses. Pagination returned all 5 users over 3 pages, each once |
| Least privilege | The role has only `GetItem`/`Scan` on the table ARN. Invokes are limited to this API's `SourceArn` |
| Performance | Cold start 78 ms init. First DynamoDB call 713 ms, warm calls 2–7 ms. Peak memory 94 of 1,024 MB |
| Release | `1 to change` (only `source_code_hash`), live in 6 s at the same URL, then reverted |
| Cleanup | `19 destroyed`, then the state bucket was emptied and deleted. Nothing is left in AWS |

> [!IMPORTANT]
> A code release changes only `source_code_hash`. Terraform zips `app/handler.py` again on every plan, so there is no build step to forget. If the plan says `No changes`, your edit was not saved.

## Production gaps

This is a disposable lab. Each gap below matches a skip in [`.checkov.yaml`](terraform/.checkov.yaml).

- **No auth** (CKV_AWS_309): add a JWT authorizer, because `/users` returns emails.
- **Deletion protection off:** turn it on, and add `prevent_destroy` for data that matters.
- **AWS managed keys** (CKV_AWS_119, 158, 173): use a customer managed key if you need key policies.
- **No X-Ray, DLQ, VPC or code signing** (CKV_AWS_50, 116, 117, 272).
- **`Scan`:** fine at this size. Use `Query` or a GSI on large tables.
- **Seed data and deploys:** in real use, the app writes the data, and CI applies reviewed plans using OIDC credentials.

> [!CAUTION]
> The API is public and unauthenticated. Always [clean up](quickstart.md#8-cleanup), and never commit `*.tfstate`, `*.tfvars` or `dev.backend.hcl`.
