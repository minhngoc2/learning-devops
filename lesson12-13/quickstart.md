# Quickstart: Python users API on Lambda + DynamoDB

This guide takes you from an empty AWS account to a working `GET /users` API, and then back to empty. Each step has the commands to run, what to expect, and the output of a live run.

> [!NOTE]
> **About the sample output:** all of it comes from one live run in `ap-southeast-1` on 2026-10-27, with Terraform 1.16.3, AWS provider 6.70.0, TFLint 0.64.0, Checkov 3.3.30 and AWS CLI 2.36.5. Account, API and resource IDs are masked as `<account-id>`, `<api-id>` and similar, and the client IP is redacted. Request IDs and timings are real, so you can match one request across the curl output, the function log and the access log. For the whole run in one place, including the issues found along the way, see [`evidence/run-log.md`](evidence/run-log.md).

| Step | What you do | AWS cost |
| --- | --- | --- |
| [0](#0-prepare-your-terminal) | Check tools, credentials and shell settings | None |
| [1](#1-create-the-state-bucket-once) | Create the S3 bucket for Terraform state | Cents per month |
| [2](#2-connect-the-dev-stack-to-the-bucket) | Connect the dev stack to the bucket | None |
| [3](#3-test-the-app) | Run the Python unit tests | None |
| [4](#4-check-the-terraform-code) | Run fmt, validate, mocked tests, TFLint and Checkov | None |
| [5](#5-deploy) | Plan and apply 19 resources | Near zero |
| [6](#6-verify) | Call the API, read the data, logs and permissions | Near zero |
| [7](#7-release-a-change) | Ship a code change, revert it, and ship a data change | Near zero |
| [8](#8-cleanup) | Destroy the stack | None |
| [9](#9-optional-remove-the-state-bucket) | Remove the state bucket | None |

> [!NOTE]
> Run every command from the `lesson12-13/` folder, in one terminal. If a command fails, stop and read [Troubleshooting](#troubleshooting) before you continue. Your IDs, timings and request IDs will differ from the sample output.

## 0. Prepare your terminal

You need:

| Tool | Version | Used for |
| --- | --- | --- |
| Terraform | `>= 1.10, < 2.0` | Everything in `terraform/` |
| AWS CLI | v2 | Checks in step 6 |
| Python | 3.12+ | Unit tests in step 3 |
| `jq`, `curl` | Any | Reading JSON responses |
| TFLint, `uv` | Any | Optional lint and Checkov in step 4 |

Use AWS credentials that can manage S3, DynamoDB, Lambda, API Gateway, IAM roles and CloudWatch Logs. Set `AWS_PROFILE` if you don't use the default profile. Then check who you are:

```sh
aws sts get-caller-identity
```

Turn off the AWS CLI pager for this terminal:

```sh
export AWS_PAGER=""
```

> [!TIP]
> Without this setting, the AWS CLI sends its output to `less`, or to whatever `$PAGER` is set to. In some terminals, commands such as `aws dynamodb scan` then seem to print nothing. With the pager off, the output goes straight to the terminal, and `| jq` is optional.

## 1. Create the state bucket (once)

Terraform needs a place to keep its state. The `bootstrap` root creates a private S3 bucket named `lesson12-13-tfstate-<account-id>-<region>`. Bootstrap keeps its own state in a **local** file, because a bucket cannot hold the state of the code that creates it.

**1.1** Copy the example settings. Change `project` or `aws_region` if you want a different name or region:

```sh
cp terraform/bootstrap/bootstrap.tfvars.example terraform/bootstrap/bootstrap.tfvars
```

**1.2** Download the providers and run the mocked tests (this makes no AWS calls):

```sh
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap test
```

**1.3** Plan, read the plan, then apply it:

```sh
terraform -chdir=terraform/bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform -chdir=terraform/bootstrap apply bootstrap.tfplan
```

Expect `6 to add`: the bucket, versioning, a lifecycle rule, encryption, a public access block and an HTTPS-only policy.

**1.4** Print the bucket name. You need it in step 2:

```sh
terraform -chdir=terraform/bootstrap output -raw state_bucket
```

> [!WARNING]
> Keep `terraform/bootstrap/terraform.tfstate`. Git ignores it, and it is the only record that Terraform manages the bucket.

<details>
<summary>Sample output</summary>

```text
$ terraform -chdir=terraform/bootstrap test
tests/bootstrap.tftest.hcl... in progress
  run "bucket_name_format"... pass
  run "reject_bad_project"... pass
tests/bootstrap.tftest.hcl... pass

Success! 2 passed, 0 failed.

$ terraform -chdir=terraform/bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
Plan: 6 to add, 0 to change, 0 to destroy.

$ terraform -chdir=terraform/bootstrap apply bootstrap.tfplan
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

$ terraform -chdir=terraform/bootstrap output -raw state_bucket
lesson12-13-tfstate-<account-id>-ap-southeast-1

$ terraform -chdir=terraform/bootstrap state list
data.aws_caller_identity.current
module.state_bucket.aws_s3_bucket.this
module.state_bucket.aws_s3_bucket_lifecycle_configuration.this
module.state_bucket.aws_s3_bucket_policy.tls_only
module.state_bucket.aws_s3_bucket_public_access_block.this
module.state_bucket.aws_s3_bucket_server_side_encryption_configuration.this
module.state_bucket.aws_s3_bucket_versioning.this
```

</details>

## 2. Connect the dev stack to the bucket

**2.1** Copy the two example files. Git ignores the copies:

```sh
cp terraform/environments/dev/dev.backend.hcl.example terraform/environments/dev/dev.backend.hcl
cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

**2.2** Edit `terraform/environments/dev/dev.backend.hcl`. Set `bucket` to the name from step 1.4, and keep `region` the same as the bucket's region:

```hcl
bucket       = "lesson12-13-tfstate-<account-id>-ap-southeast-1"
key          = "dev/terraform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

`dev.tfvars` already has `lambda_memory_size = 1024` (the assignment's 1 GB) and `seed_users = true`. You don't need to change it.

**2.3** Initialize the dev stack with the S3 backend:

```sh
terraform -chdir=terraform/environments/dev init -backend-config=dev.backend.hcl
```

`init` must print `Successfully configured the backend "s3"!`.

<details>
<summary>Sample output</summary>

```text
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
Initializing modules...
Initializing provider plugins...
- Using previously-installed hashicorp/archive v2.8.1
- Using previously-installed hashicorp/aws v6.70.0

Terraform has been successfully initialized!
```

</details>

> [!IMPORTANT]
> If that line is missing, Terraform is using local state. This happens when `terraform/environments/dev/backend.tf` is missing or renamed, for example to `backend.hcl`. Terraform reads only `*.tf` files, so it ignores the `backend "s3" {}` block, and it does not show an error. See [Troubleshooting](#troubleshooting).

## 3. Test the app

```sh
python3 -m unittest discover -s app -v
```

The tests replace DynamoDB with an in-memory fake table, so they need no AWS credentials and no `boto3`. They cover listing, pagination, lookup by id, number encoding, bad input (`400`) and AWS errors (`500`, with no internal details in the response).

There is no build step. Terraform zips `app/handler.py` into `build/function.zip` on every plan, and the Lambda Python runtime already includes `boto3`.

<details>
<summary>Sample output</summary>

```text
test_aws_error_is_500_without_details ... ok
test_bad_cursor ... ok
test_bad_limit ... ok
test_get_missing_user ... ok
test_get_user ... ok
test_health ... ok
test_list_users ... ok
test_numbers_become_json_numbers ... ok
test_pagination_walks_every_user_once ... ok
test_unknown_route ... ok
----------------------------------------------------------------------
Ran 10 tests in 0.002s

OK
```

</details>

## 4. Check the Terraform code

These checks make no AWS calls and create nothing.

**4.1** Format, validate and run the mocked tests:

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
```

**4.2** Optional: lint and security scan:

```sh
tflint --chdir=terraform --init
tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
uvx checkov --config-file terraform/.checkov.yaml -d terraform
```

> [!NOTE]
> `--config` must be an absolute path, which is why the command uses `$PWD`. With `--recursive`, TFLint ignores a relative path without warning and skips the AWS rules.

**4.3** Optional: test the modules and bootstrap one at a time. Together with the dev root, this makes 16 runs:

```sh
for d in bootstrap modules/dynamodb-table modules/state-bucket; do
  terraform -chdir=terraform/$d init -backend=false
  terraform -chdir=terraform/$d test
done
```

<details>
<summary>Sample output</summary>

`fmt` and `tflint` print nothing when there are no issues.

```text
$ terraform fmt -check -recursive terraform
$ terraform -chdir=terraform/environments/dev validate
Success! The configuration is valid.

$ terraform -chdir=terraform/environments/dev test
  run "users_api"... pass
  run "lambda_settings"... pass
  run "no_seed"... pass
  run "lambda_function_module"... pass
  run "api_gateway_module"... pass
  run "reject_bad_route"... pass
  run "reject_bad_lambda_inputs"... pass
  run "reject_bad_project"... pass
Success! 8 passed, 0 failed.

$ for d in bootstrap modules/dynamodb-table modules/state-bucket; do …; done
Success! 2 passed, 0 failed.      # bootstrap
Success! 3 passed, 0 failed.      # modules/dynamodb-table
Success! 3 passed, 0 failed.      # modules/state-bucket

$ tflint --chdir=terraform --init
All plugins are already installed
$ tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
$ uvx checkov --config-file terraform/.checkov.yaml -d terraform
[ terraform framework ]: 100%|████████████████████|[27/27]
terraform scan results:

Passed checks: 43, Failed checks: 0, Skipped checks: 0

Check: CKV_AWS_76: "Ensure API Gateway has Access Logging enabled"
        PASSED for resource: module.api_gateway.aws_apigatewayv2_stage.default
Check: CKV_AWS_364: "Ensure that AWS Lambda function permissions delegated to AWS services are limited by SourceArn or SourceAccount"
        PASSED for resource: module.api_gateway.aws_lambda_permission.api
Check: CKV_AWS_28: "Ensure DynamoDB point in time recovery (backup) is enabled"
        PASSED for resource: module.users_table.aws_dynamodb_table.this
Check: CKV_AWS_355: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"
        PASSED for resource: module.lambda_function.aws_iam_role_policy.inline["users-table-read"]
Check: CKV_AWS_363: "Ensure Lambda Runtime is not deprecated"
        PASSED for resource: module.lambda_function.aws_lambda_function.this
Check: CKV_AWS_53/54/55/56: S3 public access block (ACLs, policy, ignore, restrict)
        PASSED for resource: module.state_bucket.aws_s3_bucket_public_access_block.this
...
```

`Skipped checks: 0` counts only inline skips. The accepted lab findings are skipped in `terraform/.checkov.yaml`, each with a reason. The passed checks cover logging and retention, least-privilege IAM (no `*` actions or resources, no privilege escalation or data exfiltration), invokes limited by `SourceArn`, PITR, encryption, S3 public access and versioning.

</details>

## 5. Deploy

**5.1** Make a plan and save it to a file:

```sh
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -out=dev.tfplan
```

**5.2** Read the plan. Expect `19 to add`:

| Module | Resources |
| --- | --- |
| `users_table` | 1 DynamoDB table |
| root | 5 seed items (`u001`–`u005`) |
| `lambda_function` | IAM role, `AWSLambdaBasicExecutionRole` attachment, `users-table-read` inline policy, log group, function |
| `api_gateway` | HTTP API, integration, 3 routes, `$default` stage, access log group, Lambda permission |

In the plan, check three things:

- the function has `memory_size = 1024`
- `TABLE_NAME` is `lesson12-13-dev-users`
- the role policy (`users-table-read`) is the only DynamoDB access the function gets

**5.3** Apply the saved plan. Terraform applies exactly what you reviewed:

```sh
terraform -chdir=terraform/environments/dev apply dev.tfplan
```

<details>
<summary>Sample output</summary>

```text
  # module.lambda_function.aws_lambda_function.this will be created
  + resource "aws_lambda_function" "this" {
      + architectures = ["arm64"]
      + function_name = "lesson12-13-dev"
      + handler       = "handler.lambda_handler"
      + memory_size   = 1024
      + runtime       = "python3.13"
      + timeout       = 10
      + environment {
          + variables = {
              + "LOG_LEVEL"  = "INFO"
              + "TABLE_NAME" = "lesson12-13-dev-users"
            }
        }
  # module.users_table.aws_dynamodb_table.this will be created
  + resource "aws_dynamodb_table" "this" {
      + billing_mode = "PAY_PER_REQUEST"
      + hash_key     = "id"
      + name         = "lesson12-13-dev-users"
      + point_in_time_recovery { + enabled = true }
      + server_side_encryption { + enabled = true }
    }

  # module.api_gateway.aws_lambda_permission.api will be created
  + resource "aws_lambda_permission" "api" {
      + action     = "lambda:InvokeFunction"
      + principal  = "apigateway.amazonaws.com"
      + source_arn = (known after apply)
    }
...
Plan: 19 to add, 0 to change, 0 to destroy.

$ terraform -chdir=terraform/environments/dev apply dev.tfplan
module.lambda_function.aws_cloudwatch_log_group.this: Creation complete after 0s [id=/aws/lambda/lesson12-13-dev]
module.api_gateway.aws_cloudwatch_log_group.access: Creation complete after 0s [id=/aws/apigateway/lesson12-13-dev]
module.api_gateway.aws_apigatewayv2_api.this: Creation complete after 1s [id=<api-id>]
module.api_gateway.aws_apigatewayv2_stage.default: Creation complete after 1s [id=$default]
module.lambda_function.aws_iam_role.this: Creation complete after 2s [id=lesson12-13-dev-lambda]
module.lambda_function.aws_iam_role_policy_attachment.logs: Creation complete after 0s
module.users_table.aws_dynamodb_table.this: Creation complete after 8s [id=lesson12-13-dev-users]
aws_dynamodb_table_item.seed_user["u001"]: Creation complete after 1s [id=lesson12-13-dev-users,u001]
... (u002–u005 the same)
module.lambda_function.aws_iam_role_policy.inline["users-table-read"]: Creation complete after 1s
module.lambda_function.aws_lambda_function.this: Creation complete after 8s [id=lesson12-13-dev]
module.api_gateway.aws_lambda_permission.api: Creation complete after 1s [id=AllowInvokeFrom-lesson12-13-dev]
module.api_gateway.aws_apigatewayv2_integration.lambda: Creation complete after 1s [id=<integration-id>]
module.api_gateway.aws_apigatewayv2_route.routes["GET /users/{id}"]: Creation complete after 0s [id=<route-id>]
module.api_gateway.aws_apigatewayv2_route.routes["GET /health"]: Creation complete after 0s [id=<route-id>]
module.api_gateway.aws_apigatewayv2_route.routes["GET /users"]: Creation complete after 0s [id=<route-id>]

Apply complete! Resources: 19 added, 0 changed, 0 destroyed.

Outputs:

access_log_group_name = "/aws/apigateway/lesson12-13-dev"
api_url = "https://<api-id>.execute-api.ap-southeast-1.amazonaws.com"
aws_region = "ap-southeast-1"
function_name = "lesson12-13-dev"
log_group_name = "/aws/lambda/lesson12-13-dev"
table_name = "lesson12-13-dev-users"
```

</details>

**5.4** Check that the state is in S3, not on your disk:

```sh
aws s3 ls "s3://$(terraform -chdir=terraform/bootstrap output -raw state_bucket)/dev/"
ls terraform/environments/dev/terraform.tfstate   # expect: No such file or directory
```

<details>
<summary>Sample output</summary>

```text
2026-10-27 11:49:52      38746 terraform.tfstate
ls: terraform/environments/dev/terraform.tfstate: No such file or directory
```

</details>

## 6. Verify

**6.1** Set a shell helper and some variables. Steps 6 to 8 use them, so set them again if you open a new terminal:

```sh
export AWS_PAGER=""
tf() { terraform -chdir=terraform/environments/dev "$@"; }   # shorthand, works in bash and zsh
API_URL="$(tf output -raw api_url)"
REGION="$(tf output -raw aws_region)"
TABLE="$(tf output -raw table_name)"
FUNCTION="$(tf output -raw function_name)"
echo "$API_URL $REGION $TABLE $FUNCTION"
```

The `echo` should print four values. If one is empty, the AWS CLI fails with `Invalid endpoint`, or `curl` fails before it reaches AWS.

### 6.2 The API

```sh
curl -i "$API_URL/health"
curl -s "$API_URL/users" | jq
curl -s "$API_URL/users/u002" | jq
curl -i "$API_URL/users/u999"
curl -i "$API_URL/users?limit=500"
curl -i "$API_URL/unknown"
```

Expected status codes, in order: `200`, `200`, `200`, `404`, `400`, `404`.

<details>
<summary>Sample output</summary>

`Scan` returns items in hash order, so your order may differ. The last `404` body comes from API Gateway: no route matched, so Lambda never ran.

```text
$ curl -i "$API_URL/health"
HTTP/2 200
date: Tue, 27 Oct 2026 11:40:39 GMT
content-type: application/json
content-length: 15
apigw-requestid: F5sUyiJhyQ0EP4A=

{"status":"ok"}

$ curl -s "$API_URL/users" | jq
{
  "users": [
    { "email": "em.vo@example.com",     "id": "u005", "role": "viewer",    "name": "Em Vo" },
    { "email": "chi.le@example.com",    "id": "u003", "role": "developer", "name": "Chi Le" },
    { "id": "u002", "role": "developer", "email": "binh.tran@example.com", "name": "Binh Tran" },
    { "email": "an.nguyen@example.com", "role": "admin", "id": "u001",     "name": "An Nguyen" },
    { "role": "devops", "email": "dung.pham@example.com", "id": "u004",    "name": "Dung Pham" }
  ],
  "count": 5
}

$ curl -s "$API_URL/users/u002" | jq
{ "id": "u002", "role": "developer", "email": "binh.tran@example.com", "name": "Binh Tran" }

$ curl -i "$API_URL/users/u999"
HTTP/2 404
content-type: application/json
apigw-requestid: F5sWHhwQyQ0EP3A=

{"error":"user not found"}

$ curl -i "$API_URL/users?limit=500"
HTTP/2 400
content-type: application/json
apigw-requestid: F5sWij_-SQ0EPqA=

{"error":"limit must be an integer between 1 and 100"}

$ curl -i "$API_URL/unknown"
HTTP/2 404
content-type: application/json
apigw-requestid: F5sW9i5RyQ0EP8g=

{"message":"Not Found"}
```

The keys inside each user are in a different order each time, because the handler builds the JSON from DynamoDB's attribute map. JSON clients don't depend on key order.

</details>

### 6.3 Pagination

```sh
PAGE1="$(curl -s "$API_URL/users?limit=2")"; echo "$PAGE1" | jq -c
NEXT="$(echo "$PAGE1" | jq -r .next)"
curl -s "$API_URL/users?limit=2&next=$NEXT" | jq -c
```

Keep following `next` until a page doesn't have one. Together, the pages return all 5 users, each once.

<details>
<summary>Sample output</summary>

```text
$ PAGE1="$(curl -s "$API_URL/users?limit=2")"; echo "$PAGE1" | jq -c
{"users":[{"email":"em.vo@example.com","id":"u005","role":"viewer","name":"Em Vo"},{"email":"chi.le@example.com","id":"u003","role":"developer","name":"Chi Le"}],"count":2,"next":"eyJpZCI6ICJ1MDAzIn0"}

$ curl -s "$API_URL/users?limit=2&next=$NEXT" | jq -c
{"users":[{"id":"u002","role":"developer","email":"binh.tran@example.com","name":"Binh Tran"},{"email":"an.nguyen@example.com","role":"admin","id":"u001","name":"An Nguyen"}],"count":2,"next":"eyJpZCI6ICJ1MDAxIn0"}

$ curl -s "$API_URL/users?limit=2&next=eyJpZCI6ICJ1MDAxIn0" | jq -c
{"users":[{"role":"devops","email":"dung.pham@example.com","id":"u004","name":"Dung Pham"}],"count":1}
```

| Page | Users | `next` |
| --- | --- | --- |
| 1 | u005, u003 | `eyJpZCI6ICJ1MDAzIn0` = `{"id": "u003"}` |
| 2 | u002, u001 | `eyJpZCI6ICJ1MDAxIn0` = `{"id": "u001"}` |
| 3 | u004 | none, so this is the last page |

The cursor is DynamoDB's `LastEvaluatedKey`, base64-encoded. The 3 pages return all 5 users, each once.

</details>

### 6.4 The data in DynamoDB

```sh
aws dynamodb scan --table-name "$TABLE" --region "$REGION" --select COUNT
aws dynamodb get-item --table-name "$TABLE" --region "$REGION" --key '{"id":{"S":"u001"}}'
```

`Count` should be `5`. `get-item` shows the typed form that DynamoDB stores, such as `{"name":{"S":"An Nguyen"}}`. The handler converts it back to plain JSON.

<details>
<summary>Sample output</summary>

```json
{ "Count": 5, "ScannedCount": 5, "ConsumedCapacity": null }

{
  "Item": {
    "email": { "S": "an.nguyen@example.com" },
    "role":  { "S": "admin" },
    "id":    { "S": "u001" },
    "name":  { "S": "An Nguyen" }
  }
}
```

</details>

### 6.5 Logs

```sh
aws logs tail "$(tf output -raw log_group_name)" --since 10m --region "$REGION"
aws logs tail "$(tf output -raw access_log_group_name)" --since 10m --region "$REGION"
```

<details>
<summary>Sample output</summary>

The function log uses JSON. Each request has three records: `platform.start`, the handler's `request` line, and `platform.report`. Only the first request after a deploy has `initDurationMs`, because it is a cold start. The first two requests, in full:

```text
{"time":"2026-10-27T11:40:39.869Z","type":"platform.initStart","record":{"initializationType":"on-demand","phase":"init","runtimeVersion":"python:3.13.mainlinev2.v43","functionName":"lesson12-13-dev","functionVersion":"$LATEST","instanceMaxMemory":1073741824}}
{"time":"2026-10-27T11:40:39.950Z","type":"platform.start","record":{"requestId":"51b37a94-d3eb-4a84-9c26-f6f4db341375","version":"$LATEST"}}
{"timestamp": "2026-10-27T11:40:39Z", "level": "INFO", "message": "request", "logger": "root", "requestId": "51b37a94-d3eb-4a84-9c26-f6f4db341375", "route": "GET /health", "request_id": "F5sUyiJhyQ0EP4A="}
{"time":"2026-10-27T11:40:39.953Z","type":"platform.report","record":{"requestId":"51b37a94-d3eb-4a84-9c26-f6f4db341375","metrics":{"durationMs":2.24,"billedDurationMs":81,"memorySizeMB":1024,"maxMemoryUsedMB":32,"initDurationMs":77.888},"status":"success"}}
{"time":"2026-10-27T11:40:42.327Z","type":"platform.start","record":{"requestId":"f7110e21-1420-4c5a-ae04-bfb86a49d9ff","version":"$LATEST"}}
{"timestamp": "2026-10-27T11:40:42Z", "level": "INFO", "message": "request", "logger": "root", "requestId": "f7110e21-1420-4c5a-ae04-bfb86a49d9ff", "route": "GET /users", "request_id": "F5sVMiwgSQ0EPwA="}
{"timestamp": "2026-10-27T11:40:42Z", "level": "INFO", "message": "Found credentials in environment variables.", "logger": "botocore.credentials", "requestId": "f7110e21-1420-4c5a-ae04-bfb86a49d9ff"}
{"time":"2026-10-27T11:40:43.041Z","type":"platform.report","record":{"requestId":"f7110e21-1420-4c5a-ae04-bfb86a49d9ff","metrics":{"durationMs":712.978,"billedDurationMs":713,"memorySizeMB":1024,"maxMemoryUsedMB":92},"status":"success"}}
```

The `platform.report` lines for every request in step 6.2:

| Request | Duration | Billed | Max memory | Notes |
| --- | --- | --- | --- | --- |
| `GET /health` | 2.2 ms | 81 ms | 32 MB | Cold start, `initDurationMs` 77.9. The init time is billed |
| `GET /users` | 713 ms | 713 ms | 92 MB | First DynamoDB call. `botocore` loads the role's credentials and opens the connection |
| `GET /users/u002` | 6.4 ms | 7 ms | 92 MB | Warm, reuses the client |
| `GET /users/u999` | 5.1 ms | 6 ms | 92 MB | Warm, `404` from the handler |
| `GET /users?limit=500` | 1.7 ms | 2 ms | 94 MB | Rejected before calling DynamoDB |
| `GET /users?limit=2` (pages) | 6–7 ms | 7–8 ms | 94 MB | Warm |

Every report shows `memorySizeMB: 1024`, the assignment's 1 GB, and the function never used more than 94 MB of it.

`request_id` in the function log matches `requestId` in the access log, so you can follow one request through both logs:

```text
{"integrationError":"-","integrationLatency":"237","latencyMs":"242","requestId":"F5sUyiJhyQ0EP4A=","routeKey":"GET /health","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"724","latencyMs":"727","requestId":"F5sVMiwgSQ0EPwA=","routeKey":"GET /users","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"36","latencyMs":"41","requestId":"F5sVyhrayQ0EP3A=","routeKey":"GET /users/{id}","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"29","latencyMs":"34","requestId":"F5sWHhwQyQ0EP3A=","routeKey":"GET /users/{id}","sourceIp":"<redacted>","status":"404"}
```

API Gateway itself adds only 3–5 ms, the difference between `latencyMs` and `integrationLatency`. On warm calls, `integrationLatency` is about 30 ms, while the function runs for 5–6 ms. The rest is the cost of invoking Lambda. The access log has no line for `/unknown`, because no route matched. New lines can take a minute to appear, which is why the last requests are not in this tail yet.

</details>

### 6.6 Invoke the function directly, without API Gateway

```sh
aws lambda invoke --region "$REGION" --function-name "$FUNCTION" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"routeKey":"GET /users/{id}","pathParameters":{"id":"u003"}}' /dev/stdout
```

The command prints two JSON objects. The first is the function's response: `statusCode` 200, and a `body` with Chi Le. The second is the CLI's own result: `"StatusCode": 200` and `"ExecutedVersion": "$LATEST"`.

<details>
<summary>Sample output</summary>

```text
{"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"email\":\"chi.le@example.com\",\"id\":\"u003\",\"role\":\"developer\",\"name\":\"Chi Le\"}"}
{
  "StatusCode": 200,
  "ExecutedVersion": "$LATEST"
}
```

The event only needs `routeKey` and `pathParameters`, because the handler routes on `routeKey` alone. The event that API Gateway sends has many more fields.

</details>

### 6.7 Check the configuration and permissions

```sh
aws lambda get-function-configuration --function-name "$FUNCTION" --region "$REGION" \
  --query '{Memory:MemorySize,Runtime:Runtime,Handler:Handler,Env:Environment.Variables}'
aws iam get-role-policy --role-name "$FUNCTION-lambda" --policy-name users-table-read
aws lambda get-policy --function-name "$FUNCTION" --region "$REGION" --query Policy --output text | jq '.Statement[0].Condition'
```

| Command | Expect |
| --- | --- |
| `get-function-configuration` | `Memory: 1024`, `python3.13`, `handler.lambda_handler`, `TABLE_NAME` and `LOG_LEVEL` |
| `get-role-policy` | Only `dynamodb:GetItem` and `dynamodb:Scan`, on the table ARN |
| `get-policy` | `AWS:SourceArn` is `arn:aws:execute-api:<region>:<account-id>:<api-id>/*/*`, so only this API can invoke the function |

<details>
<summary>Sample output</summary>

```json
{
  "Memory": 1024,
  "Runtime": "python3.13",
  "Handler": "handler.lambda_handler",
  "Env": {
    "TABLE_NAME": "lesson12-13-dev-users",
    "LOG_LEVEL": "INFO"
  }
}

{
  "RoleName": "lesson12-13-dev-lambda",
  "PolicyName": "users-table-read",
  "PolicyDocument": {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": ["dynamodb:GetItem", "dynamodb:Scan"],
        "Effect": "Allow",
        "Resource": "arn:aws:dynamodb:ap-southeast-1:<account-id>:table/lesson12-13-dev-users",
        "Sid": "ReadUsersTable"
      }
    ]
  }
}

{
  "ArnLike": {
    "AWS:SourceArn": "arn:aws:execute-api:ap-southeast-1:<account-id>:<api-id>/*/*"
  }
}
```

The role has no `PutItem`, `DeleteItem` or `Query`, and the policy names one table ARN, with no `*`. `<api-id>` is the same API ID as in `api_url`, so no other API can invoke the function.

</details>

## 7. Release a change

### 7.1 Code change

Add a `version` field to `/health`. Change both files, because the test compares the exact response body:

- `app/handler.py`: `return reply(200, {"status": "ok", "version": "v2"})`
- `app/test_handler.py`: in `test_health`, expect `{"status": "ok", "version": "v2"}`

Then test, plan, apply, and check the result:

```sh
python3 -m unittest discover -s app
tf plan -var-file=dev.tfvars -out=dev.tfplan
tf apply dev.tfplan
curl -s "$API_URL/health"
```

The plan should change only `aws_lambda_function`, with a new `source_code_hash` (`1 to change`). The URL, the function name and the table stay the same.

<details>
<summary>Sample output</summary>

```text
$ python3 -m unittest discover -s app
..........
----------------------------------------------------------------------
Ran 10 tests in 0.002s

OK

$ tf plan -var-file=dev.tfvars -out=dev.tfplan
data.archive_file.app: Read complete after 0s [id=237df89c255ae42d8a93df44b87028d2da592e91]
...
  # module.lambda_function.aws_lambda_function.this will be updated in-place
  ~ resource "aws_lambda_function" "this" {
        id                             = "lesson12-13-dev"
      ~ last_modified                  = "2026-10-27T11:38:21.536+0000" -> (known after apply)
      ~ source_code_hash               = "L+r3xFVwhjt7N1LwBzQHDILvK4oBbOxbtNYHwsFYEkA=" -> "/ZKukUCOSfa096EhSHSxpwuQZO55C8CjJ0UxFL3cPWw="
        # (30 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.

$ tf apply dev.tfplan
module.lambda_function.aws_lambda_function.this: Modifying... [id=lesson12-13-dev]
module.lambda_function.aws_lambda_function.this: Modifications complete after 6s [id=lesson12-13-dev]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

api_url = "https://<api-id>.execute-api.ap-southeast-1.amazonaws.com"

$ curl -s "$API_URL/health"
{"status":"ok","version":"v2"}
```

`api_url` is the same as in step 5, and the new code is live as soon as the apply finishes.

</details>

If the plan says `No changes`, your edit to `handler.py` was not saved.

### 7.2 Revert the code change

The `v2` field is only a release demo, so put both files back as they were:

- `app/handler.py`: `return reply(200, {"status": "ok"})`
- `app/test_handler.py`: in `test_health`, expect `{"status": "ok"}`

```sh
python3 -m unittest discover -s app
```

If the stack is still deployed, plan and apply as in 7.1. Expect `1 to change` again, because `source_code_hash` goes back to the old value, and then `/health` returns `{"status":"ok"}`. If you already ran step 8, the tests are all you need, because the next deploy uses the reverted code.

<details>
<summary>Sample output</summary>

The recorded run reverted the files after cleanup, so only the tests ran:

```text
$ python3 -m unittest discover -s app
..........
----------------------------------------------------------------------
Ran 10 tests in 0.001s

OK
```

</details>

### 7.3 Data change

Add a user to `terraform/environments/dev/seed/users.json`:

```json
{ "id": "u006", "name": "Giang Do", "email": "giang.do@example.com", "role": "viewer" }
```

Then plan and apply as in 7.1. Expect `1 to add` (`seed_user["u006"]`). The other items keep their `for_each` keys, so Terraform doesn't touch them. After the apply, `GET /users` returns `count` 6.

## 8. Cleanup

**8.1** Preview what will be destroyed:

```sh
tf plan -destroy -var-file=dev.tfvars
```

Expect `19 to destroy`, or 20 if you added `u006`. The list includes the users table and its data.

**8.2** Destroy the stack. Type `yes` when Terraform asks:

```sh
tf destroy -var-file=dev.tfvars
tf state list   # expect no output
```

This removes the table, the function, the API, the role and both log groups. The state bucket stays, and costs cents per month. Keep it if you want to deploy again later, or remove it in step 9.

> [!WARNING]
> Deleting the table also deletes its point-in-time recovery backups. In this lab, the data comes back from `seed/users.json` on the next apply.

**8.3** Optional: check in AWS that nothing is left. Each command should print `not found` or nothing:

```sh
aws dynamodb describe-table --table-name "$TABLE" --region "$REGION"
aws lambda get-function --function-name "$FUNCTION" --region "$REGION"
aws iam get-role --role-name "$FUNCTION-lambda"
aws apigatewayv2 get-apis --region "$REGION" --query "Items[?Name=='$FUNCTION'].ApiId" --output text
aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "/aws/lambda/$FUNCTION" --query 'logGroups[].logGroupName' --output text
```

<details>
<summary>Sample output</summary>

```text
$ tf plan -destroy -var-file=dev.tfvars
  # module.users_table.aws_dynamodb_table.this will be destroyed
  - resource "aws_dynamodb_table" "this" {
      - deletion_protection_enabled = false -> null
      - name                        = "lesson12-13-dev-users" -> null
      - point_in_time_recovery {
          - enabled                 = true -> null
          - recovery_period_in_days = 35 -> null
        }
    }
...
Plan: 0 to add, 0 to change, 19 to destroy.

$ tf destroy -var-file=dev.tfvars
  Enter a value: yes

aws_dynamodb_table_item.seed_user["u001"]: Destruction complete after 1s
... (u002–u005, the 3 routes, the Lambda permission and the stage, all after 1s)
module.api_gateway.aws_apigatewayv2_integration.lambda: Destruction complete after 0s
module.api_gateway.aws_cloudwatch_log_group.access: Destruction complete after 0s
module.api_gateway.aws_apigatewayv2_api.this: Destruction complete after 2s
module.lambda_function.aws_lambda_function.this: Destruction complete after 5s
module.lambda_function.aws_cloudwatch_log_group.this: Destruction complete after 0s
module.lambda_function.aws_iam_role_policy.inline["users-table-read"]: Destruction complete after 1s
module.lambda_function.aws_iam_role_policy_attachment.logs: Destruction complete after 1s
module.lambda_function.aws_iam_role.this: Destruction complete after 1s
module.users_table.aws_dynamodb_table.this: Destruction complete after 7s

Destroy complete! Resources: 19 destroyed.

$ tf state list
$ aws dynamodb describe-table --table-name "$TABLE" --region "$REGION"
An error occurred (ResourceNotFoundException) when calling the DescribeTable operation: Requested resource not found: Table: lesson12-13-dev-users not found
$ aws lambda get-function --function-name "$FUNCTION" --region "$REGION"
An error occurred (ResourceNotFoundException) when calling the GetFunction operation: Function not found: arn:aws:lambda:ap-southeast-1:<account-id>:function:lesson12-13-dev
$ aws iam get-role --role-name "$FUNCTION-lambda"
An error occurred (NoSuchEntity) when calling the GetRole operation: The role with name lesson12-13-dev-lambda cannot be found.
$ aws apigatewayv2 get-apis … --output text
$ aws logs describe-log-groups … --output text
$ curl -sS "$API_URL/health"
curl: (6) Could not resolve host: <api-id>.execute-api.ap-southeast-1.amazonaws.com
```

The table is destroyed last, because the seed items and the IAM policy depend on it. The old `api_url` no longer resolves in DNS.

</details>

> [!NOTE]
> If you turned on `deletion_protection` for the table, `destroy` fails with `ResourceInUseException`. Set it back to `false`, apply, then destroy.

## 9. Optional: remove the state bucket

> [!CAUTION]
> This permanently deletes every state version in the bucket. Do it only after step 8, when no stack keeps its state in the bucket.

The module sets `prevent_destroy`, so `terraform destroy` refuses to delete the bucket on purpose. Empty the versioned bucket first, then delete it and the local bootstrap state:

```sh
BUCKET="$(terraform -chdir=terraform/bootstrap output -raw state_bucket)"
aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: [Versions, DeleteMarkers][].{Key:Key,VersionId:VersionId}, Quiet: `true`}' \
  --output json > /tmp/lesson12-13-state-versions.json
aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/lesson12-13-state-versions.json
aws s3api delete-bucket --bucket "$BUCKET"
rm terraform/bootstrap/terraform.tfstate*
```

`delete-objects` deletes up to 1,000 versions per call. If the bucket has more, repeat the list and delete commands. If the bucket is already empty, skip `delete-objects`.

The list includes `dev/terraform.tfstate.tflock` entries as well as the state. S3-native locking writes this lock file on every plan and apply and then deletes it, which leaves versions and delete markers behind. A versioned bucket can't be deleted until both are gone. That's why the query lists `Versions` and `DeleteMarkers`.

Check that the bucket is gone. Expect `404 … Not Found`:

```sh
aws s3api head-bucket --bucket "$BUCKET"
rm /tmp/lesson12-13-state-versions.json
```

<details>
<summary>Sample output</summary>

`delete-objects` and `delete-bucket` print nothing when they succeed (`Quiet: true` reports only errors). In this run, the list had 10 entries: 2 versions of `dev/terraform.tfstate` and 8 entries for `dev/terraform.tfstate.tflock`.

```text
$ aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/lesson12-13-state-versions.json
$ aws s3api delete-bucket --bucket "$BUCKET"
$ rm terraform/bootstrap/terraform.tfstate*
$ aws s3api head-bucket --bucket "$BUCKET"
An error occurred (404) when calling the HeadBucket operation: Not Found
$ aws s3 ls | grep lesson12-13
$
```

Nothing from the lab is left in AWS.

</details>

To run the lab again, start from step 1. The bucket name is free again, so bootstrap creates the same name.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `aws …` prints nothing, but `aws … \| jq` works | The CLI pager (`less`) takes over the output | `export AWS_PAGER=""` |
| `init` doesn't print `configured the backend "s3"`, and `terraform.tfstate` appears in `environments/dev/` | `backend.tf` is missing or was renamed, so Terraform uses local state | Restore `backend.tf`, then `tf init -backend-config=dev.backend.hcl -migrate-state`, and check that `tf plan` shows `No changes` |
| `terraform fmt -check` lists `bootstrap.tfvars` | Your copy isn't formatted (fmt checks `*.tfvars` too) | `terraform fmt -recursive terraform` |
| `Invalid endpoint` from the AWS CLI | `$REGION` is empty | Set the variables in step 6.1 again |
| Release plan says `No changes` | `handler.py` was not saved | Save the file and plan again |
| TFLint passes but skips the AWS rules | `--config` is a relative path | Use `--config="$PWD/terraform/.tflint.hcl"` |
