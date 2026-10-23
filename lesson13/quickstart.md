# Quickstart: Go on Lambda + API Gateway

Run every command from `lesson13/` in one terminal. Stop if any command fails.

Requires Go 1.27.1+, Terraform `>= 1.10, < 2.0`, and AWS CLI v2. Use AWS credentials allowed to manage S3, Lambda, API Gateway, IAM roles and CloudWatch Logs; set `AWS_PROFILE` if needed.

```sh
aws sts get-caller-identity
```

## 1. Create the state bucket (once)

The `bootstrap` root keeps its own state **locally** (the bucket can't store the state that creates it) and creates `lesson13-tfstate-<account-id>-<region>`.

```sh
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap test
terraform -chdir=terraform/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=terraform/bootstrap apply bootstrap.tfplan
terraform -chdir=terraform/bootstrap output -raw state_bucket
```

Expect `6 to add`: the bucket, versioning, lifecycle rule, encryption, public access block and HTTPS-only policy.

> [!WARNING]
> Keep `terraform/bootstrap/terraform.tfstate`. It is git-ignored and is the only record that Terraform manages the bucket.

<details>
<summary>Sample output</summary>

```text
  run "bucket_name_format"... pass
  run "reject_bad_project"... pass
Success! 2 passed, 0 failed.

Plan: 6 to add, 0 to change, 0 to destroy.
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:
state_bucket = "lesson13-tfstate-<account-id>-ap-southeast-1"
```

</details>

## 2. Point the dev stack at the bucket

```sh
cp terraform/environments/dev/dev.backend.hcl.example terraform/environments/dev/dev.backend.hcl
cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

Set `bucket` in `dev.backend.hcl` to the `state_bucket` output; `region` must match. Both copies are git-ignored.

```sh
terraform -chdir=terraform/environments/dev init -backend-config=dev.backend.hcl
```

`init` should print `Successfully configured the backend "s3"!`.

> [!NOTE]
> Moving from an earlier local-state run? Add `-migrate-state` and answer `yes` when asked to copy state. Keep the old `terraform.tfstate` until `terraform state list` shows the expected resources.

## 3. Test and build the app

```sh
go -C app vet ./...
go -C app test ./...
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C app build -tags lambda.norpc -trimpath -o ../build/bootstrap .
file build/bootstrap
```

Lambda's `provided.al2023` runtime runs an executable named `bootstrap`. `GOARCH=arm64` must match the function's `architectures`. Terraform zips `build/bootstrap` into `build/function.zip`, so build before any `test`, `plan` or `apply`.

> [!NOTE]
> `./build/bootstrap` fails on macOS with `exec format error`. That is expected: it is a Linux binary.

<details>
<summary>Sample output</summary>

```text
ok  	github.com/minhngoc2/learning-devops/lesson13
build/bootstrap: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, ...
```

</details>

## 4. Check the Terraform code (no AWS calls)

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
tflint --chdir=terraform --init
tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
uvx checkov --config-file terraform/.checkov.yaml -d terraform
```

To test the reusable module on its own: `terraform -chdir=terraform/modules/state-bucket init -backend=false`, then `test`. On a checkout without `dev.backend.hcl`, use `init -backend=false` for the dev root too.

<details>
<summary>Sample output</summary>

`fmt` and `tflint` print nothing when there are no issues.

```text
Success! The configuration is valid.

  run "go_function"... pass
  run "lambda_function_module"... pass
  run "api_gateway_module"... pass
  run "reject_bad_route"... pass
  run "reject_bad_lambda_inputs"... pass
  run "reject_bad_api_inputs"... pass
  run "reject_bad_project"... pass
Success! 7 passed, 0 failed.

terraform scan results:
Passed checks: 32, Failed checks: 0, Skipped checks: 0
```

Checkov's `Skipped checks: 0` counts only inline skips. Accepted lab findings are skipped in `terraform/.checkov.yaml`, each with its reason.

</details>

## 5. Deploy

```sh
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -out=dev.tfplan
terraform -chdir=terraform/environments/dev apply dev.tfplan
```

Review the plan before applying. Expect `12 to add`: IAM role, policy attachment, 2 log groups, Lambda function, HTTP API, integration, 3 routes, stage and Lambda permission.

<details>
<summary>Sample output</summary>

```text
Plan: 12 to add, 0 to change, 0 to destroy.
...
module.lambda_function.aws_lambda_function.this: Creation complete after 19s [id=lesson13-dev]
...
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:
access_log_group_name = "/aws/apigateway/lesson13-dev"
api_url               = "https://<api-id>.execute-api.ap-southeast-1.amazonaws.com"
aws_region            = "ap-southeast-1"
function_name         = "lesson13-dev"
log_group_name        = "/aws/lambda/lesson13-dev"
```

</details>

## 6. Verify

```sh
API_URL="$(terraform -chdir=terraform/environments/dev output -raw api_url)"

curl -i "$API_URL/health"
curl -i "$API_URL/hello?name=lesson13"
curl -i -X POST "$API_URL/echo" -H 'Content-Type: application/json' -d '{"a":1}'
curl -i -X POST "$API_URL/echo" -H 'Content-Type: application/json' -d 'null'
curl -i "$API_URL/unknown"
```

Expected responses: `200`, `200`, `200`, `400`, `404`.

<details>
<summary>Sample output</summary>

```text
HTTP/2 200
content-type: application/json
apigw-requestid: FseZZgO-SQ0EP5w=

{"message":"Hello, lesson13!"}

HTTP/2 200
{"echo":{"a":1}}

HTTP/2 400
{"error":"body must be a JSON object"}

HTTP/2 404
{"message":"Not Found"}
```

</details>

Read the function logs:

```sh
REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"
aws logs tail "$(terraform -chdir=terraform/environments/dev output -raw log_group_name)" --since 10m --region "$REGION"
```

<details>
<summary>Sample output</summary>

The stream name is `<date>/<function>[<version>]<environment-id>`. One warm execution environment served every request below, so they share one stream. Only the first request is a cold start (`INIT_START`, `Init Duration`).

```text
2026-10-23T11:25:47 2026/10/23/lesson13-dev[$LATEST]1a16eb… INIT_START Runtime Version: provided:al2023.AmazonLinux2023.v193
2026-10-23T11:25:47 2026/10/23/lesson13-dev[$LATEST]1a16eb… START RequestId: 67f96136-… Version: $LATEST
2026-10-23T11:25:47 2026/10/23/lesson13-dev[$LATEST]1a16eb… {"level":"INFO","msg":"request","route":"GET /hello","request_id":"FseZZgO-SQ0EP5w="}
2026-10-23T11:25:47 2026/10/23/lesson13-dev[$LATEST]1a16eb… END RequestId: 67f96136-…
2026-10-23T11:25:47 2026/10/23/lesson13-dev[$LATEST]1a16eb… REPORT Duration: 2.07 ms  Billed Duration: 62 ms  Memory Size: 128 MB  Max Memory Used: 23 MB  Init Duration: 59.63 ms
2026-10-23T11:26:00 2026/10/23/lesson13-dev[$LATEST]1a16eb… {"level":"INFO","msg":"request","route":"POST /echo","request_id":"FsebYjozyQ0EP0g="}
2026-10-23T11:26:00 2026/10/23/lesson13-dev[$LATEST]1a16eb… REPORT Duration: 1.31 ms  Billed Duration: 2 ms  Memory Size: 128 MB  Max Memory Used: 23 MB
```

</details>

Read the API Gateway access logs:

```sh
aws logs tail "$(terraform -chdir=terraform/environments/dev output -raw access_log_group_name)" --since 10m --region "$REGION"
```

<details>
<summary>Sample output</summary>

`requestId` matches `request_id` in the function log, so you can follow one request through both. `latencyMs` is the total time at API Gateway; `integrationLatency` is the part spent in Lambda. The cold start shows as 276 ms, and warm requests take 15–19 ms. The `/unknown` 404 does not appear here.

```json
{"routeKey":"GET /hello","status":"200","latencyMs":"276","integrationLatency":"272","requestId":"FseZZgO-SQ0EP5w=","sourceIp":"<redacted>","integrationError":"-"}
{"routeKey":"POST /echo","status":"200","latencyMs":"15","integrationLatency":"11","requestId":"FsebYjozyQ0EP0g=","sourceIp":"<redacted>","integrationError":"-"}
{"routeKey":"POST /echo","status":"400","latencyMs":"19","integrationLatency":"15","requestId":"FsecKhxqSQ0EPqA=","sourceIp":"<redacted>","integrationError":"-"}
```

</details>

Invoke the function directly, without API Gateway:

```sh
aws lambda invoke --region "$REGION" \
  --function-name "$(terraform -chdir=terraform/environments/dev output -raw function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"routeKey":"GET /health"}' /dev/stdout
```

<details>
<summary>Sample output</summary>

The first object is the function's response; the second is the CLI's own result.

```json
{"statusCode":200,"headers":{"Content-Type":"application/json"},"multiValueHeaders":null,"body":"{\"status\":\"ok\"}","cookies":null}
{"StatusCode":200,"ExecutedVersion":"$LATEST"}
```

</details>

## 7. Release a code change

Edit `app/main.go` and its test in `app/main_test.go` (the test compares the exact body), then rebuild and apply:

```sh
go -C app test ./...
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C app build -tags lambda.norpc -trimpath -o ../build/bootstrap .
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -out=dev.tfplan
terraform -chdir=terraform/environments/dev apply dev.tfplan
```

The plan should show only `aws_lambda_function` with a changed `source_code_hash` (1 to change). Run step 6 again.

<details>
<summary>Sample output</summary>

After `/health` gained `"version":"v2"`:

```text
$ curl -i "$API_URL/health"
HTTP/2 200
content-type: application/json

{"status":"ok","version":"v2"}
```

</details>

## 8. Cleanup

```sh
terraform -chdir=terraform/environments/dev plan -destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev state list   # expect empty
```

Destroy removes the function, API, role and both log groups. The state bucket stays, and costs cents per month. Keep it to redeploy later, or remove it in step 9.

## 9. Optional: remove the state bucket

> [!CAUTION]
> This permanently deletes every state version in the bucket. Do it only after step 8, when no stack's state lives there.

The module sets `prevent_destroy`, so `terraform destroy` refuses on purpose. Empty the versioned bucket, then delete it and the local bootstrap state:

```sh
BUCKET="$(terraform -chdir=terraform/bootstrap output -raw state_bucket)"
aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: [Versions, DeleteMarkers][].{Key:Key,VersionId:VersionId}, Quiet: `true`}' \
  --output json > /tmp/lesson13-state-versions.json
aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/lesson13-state-versions.json
aws s3api delete-bucket --bucket "$BUCKET"
rm terraform/bootstrap/terraform.tfstate*
```

`delete-objects` takes up to 1,000 versions per call; repeat the last two list/delete commands if the bucket has more. If the bucket is already empty, skip `delete-objects`.
