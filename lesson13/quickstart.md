# Quickstart: Go on Lambda + API Gateway

Run every command from `lesson13/` in one terminal. Stop if any command fails.

Requires Go 1.27.1+, Terraform `>= 1.10, < 2.0`, and AWS CLI v2. Use AWS credentials allowed to manage S3, Lambda, API Gateway, IAM roles and CloudWatch Logs; set `AWS_PROFILE` if needed.

```sh
aws sts get-caller-identity
```

## 1. Create the state bucket (once)

The `bootstrap` root keeps its own state **locally** (the bucket can't store the state that creates it) and creates `lesson13-tfstate-<account-id>-<region>`.

Copy the variables file and adjust it if needed. Change `aws_region` to use another region, or `project` to get a different bucket name. The copy is git-ignored.

```sh
cp terraform/bootstrap/bootstrap.tfvars.example terraform/bootstrap/bootstrap.tfvars
```

```sh
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap test
terraform -chdir=terraform/bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
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

Set the shell variables first. Steps 6 and 7 use them, so set them again in any new terminal:

```sh
API_URL="$(terraform -chdir=terraform/environments/dev output -raw api_url)"
REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"
```

> [!NOTE]
> If `REGION` is empty, the AWS CLI fails with `Invalid endpoint: https://lambda..amazonaws.com`. If `API_URL` is empty, `curl` fails before it reaches AWS.

```sh
curl -i "$API_URL/health"
curl -i "$API_URL/hello?name=lesson13"
curl -i -X POST "$API_URL/echo" -H 'Content-Type: application/json' -d '{"a":1}'
curl -i -X POST "$API_URL/echo" -H 'Content-Type: application/json' -d 'null'
curl -i "$API_URL/unknown"
```

Expected responses: `200`, `200`, `200`, `400`, `404`.

<details>
<summary>Sample output</summary>

The 404 body is `{"message":"Not Found"}` from API Gateway, not the function's `{"error":"route not found"}`. No route matches, so Lambda never runs.

```text
HTTP/2 200
content-type: application/json
content-length: 15
apigw-requestid: Fs_l6iiZyQ0EP2w=

{"status":"ok"}

HTTP/2 200
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
aws logs tail "$(terraform -chdir=terraform/environments/dev output -raw log_group_name)" --since 10m --region "$REGION"
```

<details>
<summary>Sample output</summary>

The stream name is `<date>/<function>[<version>]<environment-id>`. One warm execution environment served every request below, so they share one stream. Only the first request is a cold start (`INIT_START`, `Init Duration`).

```text
2026-10-23T15:12:24 2026/10/23/lesson13-dev[$LATEST]9ebfe2… INIT_START Runtime Version: provided:al2023.AmazonLinux2023.v193
2026-10-23T15:12:24 2026/10/23/lesson13-dev[$LATEST]9ebfe2… START RequestId: fb222128-… Version: $LATEST
2026-10-23T15:12:24 2026/10/23/lesson13-dev[$LATEST]9ebfe2… {"level":"INFO","msg":"request","route":"GET /health","request_id":"Fs_l6iiZyQ0EP2w="}
2026-10-23T15:12:24 2026/10/23/lesson13-dev[$LATEST]9ebfe2… END RequestId: fb222128-…
2026-10-23T15:12:24 2026/10/23/lesson13-dev[$LATEST]9ebfe2… REPORT Duration: 8.72 ms  Billed Duration: 70 ms  Memory Size: 128 MB  Max Memory Used: 23 MB  Init Duration: 60.45 ms
2026-10-23T15:12:28 2026/10/23/lesson13-dev[$LATEST]9ebfe2… {"level":"INFO","msg":"request","route":"GET /hello","request_id":"Fs_mdgiXSQ0EPqA="}
2026-10-23T15:12:28 2026/10/23/lesson13-dev[$LATEST]9ebfe2… REPORT Duration: 1.16 ms  Billed Duration: 2 ms  Memory Size: 128 MB  Max Memory Used: 23 MB
```

</details>

Read the API Gateway access logs:

```sh
aws logs tail "$(terraform -chdir=terraform/environments/dev output -raw access_log_group_name)" --since 10m --region "$REGION"
```

<details>
<summary>Sample output</summary>

`requestId` matches `request_id` in the function log, so you can follow one request through both. `latencyMs` is the total time at API Gateway; `integrationLatency` is the part spent in Lambda. The cold start shows as 305 ms, and warm requests take 15–35 ms. The `/unknown` 404 does not appear here.

```json
{"integrationError":"-","integrationLatency":"302","latencyMs":"305","requestId":"Fs_l6iiZyQ0EP2w=","routeKey":"GET /health","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"30","latencyMs":"35","requestId":"Fs_mdgiXSQ0EPqA=","routeKey":"GET /hello","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"10","latencyMs":"15","requestId":"Fs_m1ipfyQ0EPtw=","routeKey":"POST /echo","sourceIp":"<redacted>","status":"200"}
{"integrationError":"-","integrationLatency":"12","latencyMs":"16","requestId":"Fs_nMitPSQ0EPMQ=","routeKey":"POST /echo","sourceIp":"<redacted>","status":"400"}
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

The first object is the function's response; the second is the CLI's own result. Both go to stdout with no newline between them, so pipe to `jq` to read them as two objects.

```json
{"statusCode":200,"headers":{"Content-Type":"application/json"},"multiValueHeaders":null,"body":"{\"status\":\"ok\"}","cookies":null}
{"StatusCode":200,"ExecutedVersion":"$LATEST"}
```

</details>

## 7. Release a code change

Make a small, visible change. For example, add a version to `/health`:

- `app/main.go`: `map[string]string{"status": "ok", "version": "v2"}`
- `app/main_test.go`: change the `health` case to expect `` `{"status":"ok","version":"v2"}` ``. The test compares the exact body, so it fails if you skip this.

Then test, rebuild and apply:

```sh
go -C app test ./...
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C app build -tags lambda.norpc -trimpath -o ../build/bootstrap .
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars -out=dev.tfplan
terraform -chdir=terraform/environments/dev apply dev.tfplan
```

The plan should show only `aws_lambda_function` with a changed `source_code_hash` (1 to change). If it shows `No changes`, the build step was skipped and `build/bootstrap` is still the old binary.

Then run step 6 again. The first request starts a new execution environment, so the function log shows a new stream and a new `INIT_START`.

<details>
<summary>Sample output</summary>

```text
  ~ resource "aws_lambda_function" "this" {
        id                             = "lesson13-dev"
      ~ last_modified                  = "2026-10-23T15:09:56.133+0000" -> (known after apply)
      ~ source_code_hash               = "o7OHuve6…" -> "eN8sF9+t…"
        # (30 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
...
module.lambda_function.aws_lambda_function.this: Modifications complete after 7s [id=lesson13-dev]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

$ curl -i "$API_URL/health"
HTTP/2 200
content-type: application/json
content-length: 30

{"status":"ok","version":"v2"}
```

The API URL and function name do not change, so clients need no update.

</details>

To undo the example, revert both files and repeat this step.

## 8. Cleanup

```sh
terraform -chdir=terraform/environments/dev plan -destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev state list   # expect empty
```

Destroy removes the function, API, role and both log groups. The state bucket stays, and costs cents per month. Keep it to redeploy later, or remove it in step 9.

<details>
<summary>Sample output</summary>

Terraform removes the resources that depend on others first: routes, permission and stage, then the integration, API and function, and the IAM role last. `state list` prints nothing.

```text
Plan: 0 to add, 0 to change, 12 to destroy.
...
module.lambda_function.aws_lambda_function.this: Destruction complete after 5s
module.lambda_function.aws_iam_role.this: Destruction complete after 1s

Destroy complete! Resources: 12 destroyed.

$ terraform -chdir=terraform/environments/dev state list
$
```

</details>

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
