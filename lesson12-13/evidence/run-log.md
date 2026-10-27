# Run log: lesson 12-13, 2026-10-27

This is a record of one full run of the [quickstart](../quickstart.md), against a real AWS account in `ap-southeast-1`. The outputs are trimmed. Account, API and resource IDs are masked, and the client IP is removed.

**Tools:** Terraform 1.16.3 · AWS provider 6.70.0 · archive provider 2.8.1 · TFLint 0.64.0 · Checkov 3.3.30 · Python 3.14 (unit tests) / 3.13 (Lambda) · AWS CLI 2.36.5

## Summary

| # | Step | Result |
| --- | --- | --- |
| 1 | Bootstrap state bucket | 6 added, bootstrap tests 2/2 |
| 2 | Lint and scan | TFLint clean, Checkov 43 passed / 0 failed |
| 3 | Deploy | Plan `19 to add`, apply `19 added` |
| 4 | API checks | 6 of 6 returned the expected status |
| 5 | Pagination | 3 pages (2 + 2 + 1), all 5 users, each once |
| 6 | DynamoDB, logs, invoke, IAM | All match what is expected |
| 7 | Code release (`/health` v2) | Unit tests 10/10, `1 to change`, live API returns `v2` |
| 8 | Issues found during the run | State moved to S3. Re-run: `fmt`, `validate`, 16/16 tests, TFLint, Checkov 43/0 all clean, and `plan` shows `No changes` |
| 9 | Cleanup | Plan `19 to destroy`, then `19 destroyed`. State is empty, and AWS has nothing left |
| 10 | Remove state bucket | 10 object versions deleted, bucket deleted, local bootstrap state removed. The account is back to empty |
| 11 | Revert the release | `/health` is back to `{"status":"ok"}`. Unit tests 10/10 |

## 1. Bootstrap

```text
$ terraform -chdir=terraform/bootstrap output
state_bucket = "lesson12-13-tfstate-<account-id>-ap-southeast-1"

$ terraform -chdir=terraform/bootstrap state list
data.aws_caller_identity.current
module.state_bucket.aws_s3_bucket.this
module.state_bucket.aws_s3_bucket_lifecycle_configuration.this
module.state_bucket.aws_s3_bucket_policy.tls_only
module.state_bucket.aws_s3_bucket_public_access_block.this
module.state_bucket.aws_s3_bucket_server_side_encryption_configuration.this
module.state_bucket.aws_s3_bucket_versioning.this
```

## 2. Lint and scan

```text
$ tflint --chdir=terraform --init
All plugins are already installed
$ tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
(no output)

$ uvx checkov --config-file terraform/.checkov.yaml -d terraform
[ terraform framework ]: 100%|████████████████████|[27/27]
terraform scan results:
Passed checks: 43, Failed checks: 0, Skipped checks: 0
```

Checkov passed checks that cover encryption, public access, IAM wildcards, privilege escalation, log retention, Lambda permissions limited by `SourceArn`, PITR, and a runtime that is not deprecated.

## 3. Deploy

```text
$ terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -out=dev.tfplan
Plan: 19 to add, 0 to change, 0 to destroy.

$ terraform -chdir=terraform/environments/dev apply dev.tfplan
module.api_gateway.aws_apigatewayv2_api.this: Creation complete after 1s [id=<api-id>]
module.users_table.aws_dynamodb_table.this: Creation complete after 8s [id=lesson12-13-dev-users]
aws_dynamodb_table_item.seed_user["u001"..."u005"]: Creation complete after 1s
module.lambda_function.aws_lambda_function.this: Creation complete after 8s [id=lesson12-13-dev]
module.api_gateway.aws_apigatewayv2_route.routes[...]: Creation complete after 0s (x3)

Apply complete! Resources: 19 added, 0 changed, 0 destroyed.

api_url = "https://<api-id>.execute-api.ap-southeast-1.amazonaws.com"
```

The whole apply took about 20 s. Terraform creates the table first, then the seed items and the IAM inline policy (which needs the table ARN), then the function, then the integration and routes.

## 4. API checks

| Request | Expected | Got |
| --- | --- | --- |
| `GET /health` | `200` | `200 {"status":"ok"}` |
| `GET /users` | `200`, 5 users | `200`, `"count": 5` |
| `GET /users/u002` | `200` | `200` Binh Tran |
| `GET /users/u999` | `404` | `404 {"error":"user not found"}` |
| `GET /users?limit=500` | `400` | `400 {"error":"limit must be an integer between 1 and 100"}` |
| `GET /unknown` | `404` from API Gateway | `404 {"message":"Not Found"}` |

## 5. Pagination

```text
page 1  limit=2                     u005, u003   next=eyJpZCI6ICJ1MDAzIn0  ({"id": "u003"})
page 2  limit=2&next=…MDAzIn0       u002, u001   next=eyJpZCI6ICJ1MDAxIn0  ({"id": "u001"})
page 3  limit=2&next=…MDAxIn0       u004         (no next)
```

## 6. Data, logs, direct invoke, IAM

```text
$ aws dynamodb scan --table-name "$TABLE" --region "$REGION" --select COUNT
{ "Count": 5, "ScannedCount": 5, "ConsumedCapacity": null }

$ aws dynamodb get-item … --key '{"id":{"S":"u001"}}'
{ "Item": { "email": {"S":"an.nguyen@example.com"}, "role": {"S":"admin"}, "id": {"S":"u001"}, "name": {"S":"An Nguyen"} } }
```

The Lambda `platform.report` metrics:

| Request | Duration | Billed | Max memory | Notes |
| --- | --- | --- | --- | --- |
| `GET /health` (first) | 2.2 ms | 81 ms | 32 MB | Cold start: `initDurationMs` 77.9 |
| `GET /users` (first) | 713 ms | 713 ms | 92 MB | Creates the `boto3` client and its credentials |
| `GET /users/{id}` | 6.4 ms | 7 ms | 92 MB | Warm |
| `GET /users?limit=500` | 1.7 ms | 2 ms | 94 MB | Rejected before calling DynamoDB |

Each function log has a `request_id` that matches `requestId` in the API Gateway access log. For example, `F5sUyiJhyQ0EP4A=` is `GET /health`, with `integrationLatency` 237 ms. `/unknown` has no line in either log.

```text
$ aws lambda invoke … --payload '{"routeKey":"GET /users/{id}","pathParameters":{"id":"u003"}}' /dev/stdout
{"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": "{\"email\":\"chi.le@example.com\",\"id\":\"u003\",\"role\":\"developer\",\"name\":\"Chi Le\"}"}
{ "StatusCode": 200, "ExecutedVersion": "$LATEST" }

$ aws lambda get-function-configuration … --query '{Memory:…,Runtime:…,Handler:…,Env:…}'
{ "Memory": 1024, "Runtime": "python3.13", "Handler": "handler.lambda_handler",
  "Env": { "TABLE_NAME": "lesson12-13-dev-users", "LOG_LEVEL": "INFO" } }

$ aws iam get-role-policy --role-name lesson12-13-dev-lambda --policy-name users-table-read
"Action": ["dynamodb:GetItem", "dynamodb:Scan"],
"Resource": "arn:aws:dynamodb:ap-southeast-1:<account-id>:table/lesson12-13-dev-users"

$ aws lambda get-policy … | jq '.Statement[0].Condition'
{ "ArnLike": { "AWS:SourceArn": "arn:aws:execute-api:ap-southeast-1:<account-id>:<api-id>/*/*" } }
```

## 7. Code release

The change was in `app/handler.py` and `app/test_handler.py`: `/health` now returns `"version": "v2"`.

```text
$ python3 -m unittest discover -s app
Ran 10 tests in 0.002s
OK

$ tf plan -var-file=dev.tfvars -out=dev.tfplan
  ~ source_code_hash = "L+r3xFVwhjt7N1LwBzQHDILvK4oBbOxbtNYHwsFYEkA=" -> "/ZKukUCOSfa096EhSHSxpwuQZO55C8CjJ0UxFL3cPWw="
Plan: 0 to add, 1 to change, 0 to destroy.

$ tf apply dev.tfplan
module.lambda_function.aws_lambda_function.this: Modifications complete after 6s
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

$ curl -s "$API_URL/health"
{"status":"ok","version":"v2"}
```

The API URL stayed the same. The change was reverted after cleanup (see section 11).

## 8. Issues found and fixed

### 8.1 The dev state was local, not in S3

**Symptom:** `terraform.tfstate` appeared in `terraform/environments/dev/`, and the state bucket had no objects.

**Cause:** the backend block was in `backend.hcl` instead of `backend.tf`. Terraform loads only `*.tf` files, so it never saw `backend "s3" {}`. It used the local backend and gave no error, and `-backend-config=dev.backend.hcl` did nothing.

**Fix:**

```text
$ mv terraform/environments/dev/backend.hcl terraform/environments/dev/backend.tf
$ terraform -chdir=terraform/environments/dev init -backend-config=dev.backend.hcl -migrate-state -force-copy
Terraform has been successfully initialized!

$ aws s3 ls s3://lesson12-13-tfstate-<account-id>-ap-southeast-1/ --recursive
2026-10-27 11:49:52      38746 dev/terraform.tfstate

$ terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -detailed-exitcode
No changes. Your infrastructure matches the configuration.      (exit 0)
```

After the migration, delete the leftover local `terraform.tfstate*` files in `environments/dev/`, so no one reads the out-of-date copy by mistake.

**Lesson:** after `init`, look for `Successfully configured the backend "s3"!`. Quickstart steps 2.3 and 5.4 check this, and the troubleshooting table covers the fix.

### 8.2 `aws` commands printed nothing unless piped to `jq`

**Cause:** AWS CLI v2 sends its output through a pager (`$PAGER`, usually `less`) unless `AWS_PAGER` is set. In some terminals, the output then seems to disappear.

**Fix:** `export AWS_PAGER=""` (quickstart step 0). To make it permanent, run `aws configure set cli_pager ""`.

### 8.3 `terraform fmt -check` listed `bootstrap.tfvars`

`bootstrap.tfvars`, copied from the example and then edited, was not aligned. `fmt` checks `*.tfvars` too, so `terraform fmt -recursive terraform` fixed it.

## 9. Cleanup

This ran after the state moved to S3, so the destroy read and wrote the remote state.

```text
$ tf plan -destroy -var-file=dev.tfvars
Plan: 0 to add, 0 to change, 19 to destroy.

$ tf destroy -var-file=dev.tfvars
  Enter a value: yes
aws_dynamodb_table_item.seed_user["u001"..."u005"]: Destruction complete after 1s
module.api_gateway.aws_apigatewayv2_route.routes[...]: Destruction complete after 1s (x3)
module.api_gateway.aws_lambda_permission.api: Destruction complete after 1s
module.api_gateway.aws_apigatewayv2_stage.default: Destruction complete after 1s
module.api_gateway.aws_apigatewayv2_integration.lambda: Destruction complete after 0s
module.api_gateway.aws_apigatewayv2_api.this: Destruction complete after 2s
module.lambda_function.aws_lambda_function.this: Destruction complete after 5s
module.lambda_function.aws_iam_role_policy.inline["users-table-read"]: Destruction complete after 1s
module.lambda_function.aws_iam_role.this: Destruction complete after 1s
module.users_table.aws_dynamodb_table.this: Destruction complete after 7s

Destroy complete! Resources: 19 destroyed.
```

Terraform destroys in the reverse order of creation. It removes the seed items, routes, permission and stage first, then the API and the function, then the IAM policies and role. The table goes last, because the IAM policy and the seed items depend on its ARN. The whole destroy took about 15 s.

The destroy plan listed what would be lost. The table had `point_in_time_recovery` with `recovery_period_in_days = 35`, but deleting the table also removes its PITR backups. So in this lab, the 5 seed users can only come back from `seed/users.json`.

### Check that nothing is left

```text
$ tf state list
(no output)

$ aws dynamodb describe-table --table-name lesson12-13-dev-users
ResourceNotFoundException: Table: lesson12-13-dev-users not found
$ aws lambda get-function --function-name lesson12-13-dev
ResourceNotFoundException: Function not found
$ aws iam get-role --role-name lesson12-13-dev-lambda
NoSuchEntity: The role with name lesson12-13-dev-lambda cannot be found.
$ aws apigatewayv2 get-apis --query "Items[?Name=='lesson12-13-dev'].ApiId" --output text
(no output)
$ aws logs describe-log-groups --log-group-name-prefix /aws/lambda/lesson12-13        (no output)
$ aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/lesson12-13    (no output)
$ curl -sS https://<api-id>.execute-api.ap-southeast-1.amazonaws.com/health
curl: (6) Could not resolve host: <api-id>.execute-api.ap-southeast-1.amazonaws.com
```

After the destroy, the bucket still held `dev/terraform.tfstate` (2,719 bytes, now an empty state) and its older versions. Step 10 removed them.

## 10. Remove the state bucket

The state-bucket module sets `prevent_destroy`, so `terraform destroy` can't delete the bucket. It was emptied and deleted with the AWS CLI instead (quickstart step 9):

```text
$ BUCKET="$(terraform -chdir=terraform/bootstrap output -raw state_bucket)"
$ aws s3api list-object-versions --bucket "$BUCKET" \
    --query '{Objects: [Versions, DeleteMarkers][].{Key:Key,VersionId:VersionId}, Quiet: `true`}' \
    --output json > /tmp/lesson12-13-state-versions.json
$ aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/lesson12-13-state-versions.json
(no output: Quiet=true reports only errors)
$ aws s3api delete-bucket --bucket "$BUCKET"
(no output)
$ rm terraform/bootstrap/terraform.tfstate*
```

The list had 10 entries:

| Key | Entries | What they are |
| --- | --- | --- |
| `dev/terraform.tfstate` | 2 | The state from before and after the destroy |
| `dev/terraform.tfstate.tflock` | 8 | Versions and delete markers left by S3-native locking. Every plan and apply writes the lock file and then deletes it |

A versioned bucket must have no versions and no delete markers before `delete-bucket` works. That is why the query lists both `Versions` and `DeleteMarkers`.

### Check that nothing is left

```text
$ aws s3api head-bucket --bucket lesson12-13-tfstate-<account-id>-ap-southeast-1
An error occurred (404) when calling the HeadBucket operation: Not Found
$ aws s3 ls | grep lesson12-13
(no output)
$ ls terraform/bootstrap/ | grep tfstate
(no output)
```

The account has nothing left from the lab. To run the lab again, start from quickstart step 1. The bucket name is free again, so bootstrap creates the same name.

## 11. Revert the release

The `v2` change from section 7 was only a release demo. After cleanup, both files went back to the original:

- `app/handler.py`: `return reply(200, {"status": "ok"})`
- `app/test_handler.py`: `test_health` expects `{"status": "ok"}`

```text
$ python3 -m unittest discover -s app
..........
----------------------------------------------------------------------
Ran 10 tests in 0.002s

OK
```

The stack was already destroyed, so there was nothing to apply. The next deploy from step 5 serves `{"status":"ok"}`. To revert while the stack is still running, follow quickstart step 7.1 with the original lines, and expect `1 to change` again.
