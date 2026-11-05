# Quickstart: e-commerce microservices on ECS Fargate

This guide takes you from an empty AWS account to a working shop (six services, a storefront, an event-driven order flow), through six failure scenarios and a release, and then back to empty. Each step has the commands to run and what to expect.

> [!NOTE]
> **About the sample output:** the live run has not been recorded yet, so every `Sample output` block for an AWS step is still a placeholder, and so are the resource counts marked `<N>`. Offline numbers (66 mocked test runs, 449 checkov checks, 9 prerendered storefront routes, 4 release-check tests) and the sample output of steps 1.2 and 4 come from real runs; those blocks are real output with the long `docker buildx` lines and absolute paths elided.

| Step | What you do | AWS cost |
| --- | --- | --- |
| [0](#0-prepare-your-terminal) | Check tools, credentials and shell settings | None |
| [1](#1-create-the-state-bucket-once) | Create the S3 bucket for Terraform state | Cents per month |
| [2](#2-connect-the-dev-stack-to-the-bucket) | Connect the dev stack to the bucket and choose email options | None |
| [3](#3-run-it-locally) | Run all six services and the storefront with Docker Compose | None |
| [4](#4-run-the-offline-checks) | Go tests, storefront build, Terraform checks, TFLint, Checkov, release-check test | None |
| [5](#5-deploy) | Create the image repositories, push `v1`, apply the stack | **Billed hourly from here**, design target about $4/day |
| [6](#6-initialize-the-database) | Confirm `db-init` ran during apply, then check the release | Running stack |
| [7](#7-publish-the-storefront) | Build the storefront and upload it to S3 | Running stack |
| [8](#8-seed-the-catalogue) | Register the demo customer and create six products | Running stack |
| [9](#9-verify) | Shop in the browser, then repeat the order flow with curl | Running stack |
| [10](#10-scenario-demos) | Pause email, fail a payment, bypass attempts, WAF rate limit, service outage | Running stack (the WAF test adds a fraction of a cent) |
| [11](#11-release-v2) | Ship image tag `v2` and check the rollout | Running stack |
| [12](#12-cleanup) | Destroy the stack | None afterwards |
| [13](#13-optional-remove-the-state-bucket) | Remove the state bucket | None |

> [!NOTE]
> Run every command from the `lesson14/` folder, in one terminal. If a command fails, stop and read [Troubleshooting](#troubleshooting) before you continue.

## 0. Prepare your terminal

You need:

| Tool | Version | Used for |
| --- | --- | --- |
| Terraform | `>= 1.10, < 2.0` | Everything in `terraform/` |
| AWS CLI | v2 | The scripts and the checks from step 5 on |
| Docker | With `buildx` and `linux/arm64` support | The local run (step 3) and the image builds (steps 5 and 11) |
| Go | `>= 1.27.3` (`go.mod`) | Unit tests in step 4 |
| Node.js + pnpm | Node 22, pnpm 12 (`packageManager` in `storefront/package.json`) | The storefront in steps 3, 4 and 7 |
| Python 3, `jq` | Any | The scripts read JSON with Python; you read it with `jq` |
| `curl` | `>= 7.76` | `check-release.sh` uses `--fail-with-body` |
| TFLint, `uv` | Any | Optional lint and Checkov in step 4 |
| `hey` | Any | Optional, for the WAF test in step 10.4 |

The Fargate tasks run on ARM64. On an Apple Silicon Mac, Docker builds `linux/arm64` natively. On an x86 machine, `docker buildx ls` must list `linux/arm64`; if it does not, install QEMU emulation with `docker run --privileged --rm tonistiigi/binfmt --install arm64`.

Use AWS credentials that can manage VPC/EC2, ECS, ECR, Elastic Load Balancing, API Gateway, Cognito, RDS, DynamoDB, SNS, SQS, S3, CloudFront, WAF, CloudWatch, IAM roles, Secrets Manager, SES and Application Auto Scaling. Set `AWS_PROFILE` if you don't use the default profile. Then check who you are:

```sh
aws sts get-caller-identity
```

Turn off the AWS CLI pager, and set the region. Every script in `scripts/` that calls AWS refuses to run without `AWS_REGION`; only the dry run (`DRY_RUN=1 build-push.sh`) and the offline test (`test_check_release.py`) work without it:

```sh
export AWS_PAGER=""
export AWS_REGION=ap-southeast-1
```

> [!TIP]
> Without `AWS_PAGER=""`, the AWS CLI sends its output to `less`, and in some terminals commands then seem to print nothing.

## 1. Create the state bucket (once)

The `bootstrap` root creates a private S3 bucket named `lesson14-tfstate-<account-id>-<region>`. Bootstrap keeps its own state in a **local** file, because a bucket cannot hold the state of the code that creates it.

**1.1** Copy the example settings. Change `project` or `aws_region` only if you want a different name or region:

```sh
cp terraform/bootstrap/bootstrap.tfvars.example terraform/bootstrap/bootstrap.tfvars
```

**1.2** Download the providers and run the mocked tests (no AWS calls):

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
<summary>Sample output (1.2, mocked tests)</summary>

```text
$ terraform -chdir=terraform/bootstrap test
tests/bootstrap.tftest.hcl... in progress
  run "bucket_name_format"... pass
  run "reject_bad_project"... pass
tests/bootstrap.tftest.hcl... tearing down
tests/bootstrap.tftest.hcl... pass

Success! 2 passed, 0 failed.
```

Steps 1.3 and 1.4: TODO: paste from live run.

</details>

## 2. Connect the dev stack to the bucket

**2.1** Copy the two example files. Git ignores the copies:

```sh
cp terraform/environments/dev/dev.backend.hcl.example terraform/environments/dev/dev.backend.hcl
cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

**2.2** Edit `terraform/environments/dev/dev.backend.hcl`. Set `bucket` to the name from step 1.4, and keep `region` the same as the bucket's region:

```hcl
bucket       = "lesson14-tfstate-<account-id>-ap-southeast-1"
key          = "dev/terraform.tfstate"
region       = "ap-southeast-1"
encrypt      = true
use_lockfile = true
```

**2.3** Choose the email options in `terraform/environments/dev/dev.tfvars`. Both lines are commented out, and both are optional:

| Setting | When set | When unset |
| --- | --- | --- |
| `alarm_email` | Subscribes this address to **two** ops topics: the regional one (`lesson14-dev-ops`) and the WAF one in us-east-1 (`lesson14-dev-waf-ops`). You get two confirmation emails after step 5 and must click both. The WAF alarm exists only when this is set | No alarm emails. The alarms still exist (except the WAF one) and show in the console |
| `notify_from_email` | Terraform creates an SES identity for it, and Notification sends real emails from it (`NOTIFY_MODE=ses`). SES emails you a verification link after step 5, and you must click it | Notification writes each email to its log instead (`NOTIFY_MODE=log`) |

> [!IMPORTANT]
> This guide assumes the account is in the **SES sandbox**. In the sandbox, SES sends only **to** verified addresses too. If you set `notify_from_email`, register the demo customer in step 8 with that same verified address. An order from an unverified address makes every send fail, and those events end up in the notification DLQ.

The other values keep the dev defaults: `image_tag = "v1"`, one task per service (autoscaling up to 4), one NAT gateway, no RDS standby, and `force_destroy = true` so `destroy` can empty the buckets and the image repositories.

**2.4** Initialize the dev stack with the S3 backend:

```sh
terraform -chdir=terraform/environments/dev init -backend-config=dev.backend.hcl
```

`init` must print `Successfully configured the backend "s3"!`.

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 3. Run it locally

`app/compose.yaml` runs all six services with local stand-ins: `postgres` for RDS, `dynamodb-local` for the cart table, `localbus` for SNS/SQS, and a Caddy `router` on port 8000 for the internal ALB's path rules. `db-init` runs once before the services start.

> [!NOTE]
> Locally there is no API Gateway, so nothing checks a JWT (`AUTH_MODE=local`). Callers send `X-Customer-Sub` and `X-Customer-Email` themselves. On AWS, a client cannot set these headers: API Gateway overwrites or removes them.

**3.1** Build and start everything (the first build takes a few minutes):

```sh
docker compose -f app/compose.yaml up --build -d
docker compose -f app/compose.yaml ps -a
```

`db-init` should show `Exited (0)`, and the other services `Up`.

**3.2** Walk the order flow with curl. The local catalogue starts empty, so create a product first:

```sh
LOCAL=http://localhost:8000
ID=(-H 'X-Customer-Sub: local-demo' -H 'X-Customer-Email: demo@example.com')
curl -s -X POST "$LOCAL/api/products" "${ID[@]}" -H 'Content-Type: application/json' \
  -d '{"id":"p-0002","name":"Phin","price_cents":6500000,"currency":"VND"}' | jq
curl -s -X PUT "$LOCAL/api/cart/items/p-0002" "${ID[@]}" -H 'Content-Type: application/json' -d '{"quantity":2}' | jq
ORDER_ID="$(curl -s -X POST "$LOCAL/api/orders" "${ID[@]}" | jq -r .id)"; echo "$ORDER_ID"
sleep 2
curl -s "$LOCAL/api/orders/$ORDER_ID" "${ID[@]}" | jq -r .status      # PAID
curl -s "$LOCAL/api/payments/$ORDER_ID" "${ID[@]}" | jq
docker compose -f app/compose.yaml logs notification | grep 'email (log mode'
```

The order starts as `PENDING_PAYMENT` and becomes `PAID` once Payment has handled `OrderCreated`. Notification logs one email per event (`OrderCreated`, then `PaymentSucceeded`).

**3.3** Run the storefront against the compose stack. `nuxt.config.ts` proxies `/api` to `http://localhost:8000`:

```sh
pnpm --dir storefront install --frozen-lockfile
pnpm --dir storefront dev
```

Open <http://localhost:3000>, register, add the product to the cart, and check out. Locally, accounts live in User Service's memory and are lost when it restarts.

**3.4** Stop everything and delete the local data:

```sh
docker compose -f app/compose.yaml down -v
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 4. Run the offline checks

These checks make no AWS calls and create nothing.

**4.1** Go and the storefront:

```sh
go -C app vet ./...
go -C app test ./...
pnpm --dir storefront install --frozen-lockfile
pnpm --dir storefront generate
```

`go test` reports `ok` for 13 packages (the `cmd/*` service mains have no tests). `pnpm generate` prerenders 9 routes (`/`, `/index.html`, `/200.html`, `/404.html`, `/login`, `/register`, `/cart`, `/checkout`, `/orders`) and writes `storefront/.output/public`.

**4.2** Format, then validate and test every root and module. The loop is the same as in `ci/github-actions.yml`:

```sh
terraform fmt -check -recursive terraform
for dir in terraform/bootstrap terraform/environments/dev terraform/modules/*; do
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" validate
  terraform -chdir="$dir" test
done
```

Expect 66 passed runs in total: bootstrap 2, the dev root 8, and 56 across the 14 modules. `init -backend=false` leaves the dev root's S3 backend from step 2 untouched. The dev root's tests set `run_db_init = false`, so the mocked apply does not call `scripts/run-db-init.sh`.

**4.3** Optional: lint and security scan:

```sh
tflint --chdir=terraform --init
tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
uvx checkov --config-file terraform/.checkov.yaml -d terraform
```

> [!NOTE]
> `--config` must be an absolute path, which is why the command uses `$PWD`. With `--recursive`, TFLint ignores a relative path without warning and skips the AWS rules.

Expect `Passed checks: 449, Failed checks: 0`. The accepted lab findings are skipped in `terraform/.checkov.yaml`, each with a reason.

**4.4** The release checker and the build script, with stubs and a dry run:

```sh
python3 scripts/test_check_release.py
DRY_RUN=1 bash scripts/build-push.sh v1
```

The test runs `check-release.sh` against command stubs (4 tests, no AWS or HTTP). The dry run prints the seven `docker buildx build --platform linux/arm64 ... --push` commands with placeholder repository URLs. `DRY_RUN` accepts only `1` (or unset); any other value fails before anything runs.

<details>
<summary>Sample output</summary>

```text
$ go -C app test ./...
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/cart	[no test files]
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/db-init	[no test files]
ok  	github.com/minhngoc2/learning-devops/lesson14/cmd/localbus	1.353s
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/notification	[no test files]
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/order	[no test files]
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/payment	[no test files]
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/product	[no test files]
?   	github.com/minhngoc2/learning-devops/lesson14/cmd/user	[no test files]
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/cart	0.531s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/config	0.511s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/dbinit	0.505s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/events	1.131s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/httpx	(cached)
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/ids	0.924s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/notification	0.895s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/order	0.920s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/payment	0.870s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/pg	0.872s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/product	0.399s
ok  	github.com/minhngoc2/learning-devops/lesson14/internal/user	0.401s

$ pnpm --dir storefront generate
...
[nitro] ℹ Prerendering 9 initial routes with crawler
[nitro]   ├─ /login (23ms)
[nitro]   ├─ /orders (23ms)
[nitro]   ├─ /checkout (23ms)
[nitro]   ├─ /cart (24ms)
[nitro]   ├─ /register (24ms)
[nitro]   ├─ /200.html (24ms)
[nitro]   ├─ /404.html (24ms)
[nitro]   ├─ / (24ms)
[nitro]   ├─ /index.html (24ms)
[nitro] ℹ Prerendered 9 routes in 0.535 seconds
[nitro] ✔ Generated public .output/public

$ terraform fmt -check -recursive terraform && (the validate/test loop, last line of each)
terraform/bootstrap               Success! 2 passed, 0 failed.
terraform/environments/dev        Success! 8 passed, 0 failed.
terraform/modules/alb-internal    Success! 4 passed, 0 failed.
terraform/modules/api-gateway     Success! 4 passed, 0 failed.
terraform/modules/cognito         Success! 3 passed, 0 failed.
terraform/modules/dynamodb-table  Success! 4 passed, 0 failed.
terraform/modules/ecr             Success! 3 passed, 0 failed.
terraform/modules/ecs-cluster     Success! 2 passed, 0 failed.
terraform/modules/ecs-service     Success! 6 passed, 0 failed.
terraform/modules/messaging       Success! 4 passed, 0 failed.
terraform/modules/network         Success! 5 passed, 0 failed.
terraform/modules/observability   Success! 4 passed, 0 failed.
terraform/modules/rds-postgres    Success! 6 passed, 0 failed.
terraform/modules/s3-cloudfront   Success! 5 passed, 0 failed.
terraform/modules/state-bucket    Success! 3 passed, 0 failed.
terraform/modules/waf             Success! 3 passed, 0 failed.

$ tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
(no output, exit 0)

$ uvx checkov --config-file terraform/.checkov.yaml -d terraform
terraform scan results:
Passed checks: 449, Failed checks: 0, Skipped checks: 0

$ python3 scripts/test_check_release.py
....
----------------------------------------------------------------------
Ran 4 tests in 13.180s

OK

$ DRY_RUN=1 bash scripts/build-push.sh v1
docker buildx build --platform linux/arm64 --build-arg SERVICE=user -t 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/user:v1 --push /…/lesson14/app
… (six more: product, cart, order, payment, notification, db-init)

IMAGE          URI
user           123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/user:v1
product        123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/product:v1
cart           123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/cart:v1
order          123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/order:v1
payment        123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/payment:v1
notification   123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/notification:v1
db-init        123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/lesson14/db-init:v1
```

</details>

## 5. Deploy

The services reference `<repository>:<image_tag>`, and ECS cannot start a task whose image does not exist yet. So the first deploy has three parts: create the repositories, push the images, then apply everything.

**5.1** Set a shell helper. Steps 5 to 13 use it, so set it again if you open a new terminal:

```sh
tf() { terraform -chdir=terraform/environments/dev "$@"; }   # works in bash and zsh
```

**5.2** Create only the seven ECR repositories (`lesson14/user`, `product`, `cart`, `order`, `payment`, `notification`, `db-init`):

```sh
tf apply -target=module.ecr -var-file=dev.tfvars
```

Read the plan and type `yes`. Expect `14 to add`: seven repositories with immutable tags and scan on push, and seven lifecycle policies. Terraform warns that resource targeting is in effect; that is expected here.

**5.3** Build and push all seven images for `linux/arm64`, tagged `v1`. This must match `image_tag` in `dev.tfvars`:

```sh
bash scripts/build-push.sh v1
```

The script logs Docker in to ECR, builds each image from `app/Dockerfile` with `--build-arg SERVICE=<name>`, pushes it, and prints an `IMAGE  URI` table at the end.

**5.4** Plan the whole stack and save the plan:

```sh
tf plan -var-file=dev.tfvars -out=dev.tfplan
```

Read the plan. Expect `<N> to add` (TODO: fill in from the live run). In the plan, check that:

- every `aws_ecs_task_definition` uses an image ending in `:v1`
- the ECS services have `assign_public_ip = false`
- the RDS instance has `publicly_accessible = false` and `multi_az = false`
- the distribution's `/api/*` origin carries the `X-Origin-Verify` custom header (its value is shown as sensitive)

**5.5** Apply the saved plan:

```sh
tf apply dev.tfplan
```

This takes a while; the RDS instance and the CloudFront distribution take the longest. Partway through, `terraform_data.db_init` runs the one-off `db-init` task (step 6 explains it) and the ECS services are created only after it succeeds. Terraform then waits until every service is stable, so a deployment that fails its health checks fails the apply. When it finishes, Terraform prints the outputs, including `cloudfront_url`. `apply` runs `scripts/run-db-init.sh`, so it needs `bash`, the AWS CLI and `AWS_REGION` in this terminal. The `run_db_init` variable (default `true`) controls this; the mocked tests set it to `false` so no AWS CLI runs. Keep it `true` for a real deploy: on a first deploy without `db-init`, the database services cannot log in, never become stable, and the apply fails.

**5.6** Confirm the emails, if you set them in step 2.3: two **AWS Notification - Subscription Confirmation** emails for `alarm_email`, and one SES verification email for `notify_from_email`. Click the link in each.

**5.7** Check that the state is in S3, not on your disk:

```sh
aws s3 ls "s3://$(terraform -chdir=terraform/bootstrap output -raw state_bucket)/dev/"
ls terraform/environments/dev/terraform.tfstate   # expect: No such file or directory
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 6. Initialize the database

The services that use PostgreSQL (`user`, `product`, `order`, `payment`) log in as their own role, `svc_<service>`, with a password from Secrets Manager. The one-off `db-init` task creates those roles and their schemas, and the services would fail at startup without them.

**6.1** You don't run anything for this on a normal deploy: `terraform apply` in step 5.5 already ran `db-init`. `terraform_data.db_init` calls `scripts/run-db-init.sh` before any ECS service is created, and again whenever the `db-init` task definition changes (a new `image_tag`). The script starts the task, waits for it to stop, prints its last log lines, and fails the apply unless the task exited 0. In the apply output, look for `db-init completed (exit 0).`

To re-run it by hand, for example after you changed the database by hand, run the same script. It reads the dev root's outputs, and `db-init` is idempotent, so running it again is safe:

```sh
bash scripts/run-db-init.sh
```

**6.2** Wait until all six services run `v1`, and check the entry path. `check-release.sh` waits for each service to be stable, checks that the primary deployment is `COMPLETED` on the expected image, that `GET /api/products` through CloudFront returns `200`, and that the raw `execute-api` URL returns `403`:

```sh
bash scripts/check-release.sh v1
```

It prints `All 6 services run v1; CloudFront serves the API; direct execute-api is refused.` and then the CloudFront URL.

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 7. Publish the storefront

The storefront is a static SPA. `pnpm generate` writes it to `storefront/.output/public`, and the files go to the storefront bucket that CloudFront serves at `/`:

```sh
pnpm --dir storefront install --frozen-lockfile
pnpm --dir storefront generate
aws s3 sync storefront/.output/public "s3://$(tf output -raw storefront_bucket_name)/" --delete
```

`--delete` removes old files from the bucket that are no longer in the build. The first upload needs no cache invalidation; later uploads do (step 11.3).

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 8. Seed the catalogue

`seed.sh` uploads `seed/images/*.png` to the images bucket under `products/`, registers (or reuses) an account through the public API, logs in, and creates the six products from `seed/products.json` with `POST /api/products`. Re-running it is safe.

Choose the demo customer's email and password now; steps 9 and 10 use them. The Cognito password policy needs at least 8 characters with upper case, lower case, a number and a symbol. If you set `notify_from_email`, use that same verified address (see step 2.3):

```sh
EMAIL='you@example.com'
PASSWORD='Demo-Passw0rd!'
CF_URL="$(tf output -raw cloudfront_url)"
bash scripts/seed.sh "$CF_URL" "$EMAIL" "$PASSWORD"
```

Expect `Registered <email>` (or `already registered; logging in`), then the ids `p-0001` to `p-0006`, one per line.

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 9. Verify

**9.1** Set the variables that steps 9 to 11 use. Set them again if you open a new terminal (with `tf`, `EMAIL` and `PASSWORD`, then log in again in 9.3 to set `TOKEN` and `AUTH`):

```sh
CF_URL="$(tf output -raw cloudfront_url)"
CLUSTER="$(tf output -raw cluster_name)"
echo "$CF_URL $CLUSTER $AWS_REGION"
```

The `echo` should print three values.

### 9.2 In the browser

Open the CloudFront URL and:

1. See the six products with their images (`/`).
2. Log in with `$EMAIL` and `$PASSWORD` (`/login`).
3. Add two products to the cart, change a quantity, and open the cart (`/cart`).
4. Check out (`/checkout`). The order page (`/orders/<id>`) polls every 2 seconds while the order is `Pending payment`, then shows `Paid` and the payment. It stops after 5 minutes (then asks you to refresh) or after 3 failed calls in a row. When your token expires, the next call sends you to `/login` and back to the page afterwards; a `403` (for example a WAF block) shows an error but keeps you logged in.
5. Open `/orders` to see the order in your list.

### 9.3 With curl

**Register and log in.** The demo customer already exists from step 8, so `register` returns `409`. In the SES sandbox, register new customers only with verified addresses:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$CF_URL/api/users/register" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,display_name:"Demo"}')"
TOKEN="$(curl -s -X POST "$CF_URL/api/users/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')" | jq -r .id_token)"
AUTH="Authorization: Bearer $TOKEN"
curl -s "$CF_URL/api/users/me" -H "$AUTH" | jq
```

The token lasts 60 minutes. If later calls return `401`, log in again: re-run the `TOKEN=` and `AUTH=` lines above, because `AUTH` holds the old token.

Register is safe to retry: if a first attempt failed halfway (the Cognito user exists but has no profile yet), registering again with the same email finishes the sign-up and returns `201`. Once the profile exists, it returns `409`.

**Products, cart and order:**

```sh
curl -s "$CF_URL/api/products" | jq -r '.[] | "\(.id)  \(.price_cents)  \(.name)"'
curl -s -X DELETE -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart" -H "$AUTH"    # 204, start empty
curl -s -X PUT "$CF_URL/api/cart/items/p-0002" -H "$AUTH" -H 'Content-Type: application/json' -d '{"quantity":2}' | jq
ORDER_ID="$(curl -s -X POST "$CF_URL/api/orders" -H "$AUTH" | jq -r .id)"; echo "$ORDER_ID"
for i in 1 2 3 4 5; do curl -s "$CF_URL/api/orders/$ORDER_ID" -H "$AUTH" | jq -r .status; sleep 2; done
curl -s "$CF_URL/api/payments/$ORDER_ID" -H "$AUTH" | jq
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart"                          # 401 without a token
```

The order starts as `PENDING_PAYMENT` and turns `PAID` within a few seconds. The payment shows `"status": "SUCCEEDED"` and `amount_cents` 13000000. The cart is empty again after checkout.

### 9.4 Email and logs

Every service logs JSON to `/ecs/lesson14-dev-<service>`. Notification logs `email (log mode, not sent)` in log mode, or `notification sent` with SES:

```sh
aws logs tail /ecs/lesson14-dev-notification --since 10m --format short
aws logs tail /ecs/lesson14-dev-order --since 10m --format short
```

With SES, check your inbox for `Order <id> received` and `Order <id> paid`.

Open the dashboard. It has rows for the edge (CloudFront and WAF), the API, the services, the data stores and the queues:

```sh
tf output -raw dashboard_url
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 10. Scenario demos

Each demo names the alarm that should change state. Alarms notify the ops topic, so with `alarm_email` set you also get an email on `ALARM` and on `OK`. To see one alarm's state:

```sh
aws cloudwatch describe-alarms --alarm-names lesson14-dev-notification-under-desired \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
```

Autoscaling owns the task count (min 1, max 4), so pausing a service means lowering the scalable target's minimum to 0 **and** setting the desired count to 0. Always restore both; Terraform's settings are min 1, max 4.

### 10.1 Email is down: pause notification

**Pause** the Notification worker:

```sh
SVC=lesson14-dev-notification
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$SVC" \
  --min-capacity 0 --max-capacity 4
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" --desired-count 0 --query 'service.desiredCount'
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"
```

**Place an order** with the curl commands from step 9.3 (`PUT` a cart item, then `POST /api/orders`). It still becomes `PAID`: Payment and Order don't depend on Notification.

**Watch the queue grow.** Each order adds two messages (`OrderCreated` and `PaymentSucceeded`):

```sh
Q_URL="$(aws sqs get-queue-url --queue-name lesson14-dev-notification-order-events --query QueueUrl --output text)"
DLQ_URL="$(aws sqs get-queue-url --queue-name lesson14-dev-notification-order-events-dlq --query QueueUrl --output text)"
aws sqs get-queue-attributes --queue-url "$Q_URL" --attribute-names ApproximateNumberOfMessages
```

After 5 minutes with no running task, `lesson14-dev-notification-under-desired` goes to `ALARM`: the alarm treats missing `RunningTaskCount` datapoints as breaching, because Container Insights stops reporting a service that has no tasks (TODO: confirm the timing in the live run).

**Restore** the worker and see the waiting emails go out:

```sh
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$SVC" \
  --min-capacity 1 --max-capacity 4
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" --desired-count 1 --query 'service.desiredCount'
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"
aws logs tail /ecs/lesson14-dev-notification --since 5m --format short
aws sqs get-queue-attributes --queue-url "$Q_URL" --attribute-names ApproximateNumberOfMessages
aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names ApproximateNumberOfMessages
```

The queue drains to `0`, and the log (or your inbox) shows the emails for the order. The DLQ stays at `0`, because the messages were waiting, not failing. A message goes to the DLQ only after 5 failed receives, for example when SES rejects every send. Then `lesson14-dev-notification-dlq-not-empty` fires within a minute. `lesson14-dev-notification-under-desired` returns to `OK`.

### 10.2 Failed payment

Product `p-0005` costs 9,999,999 cents. Ordered alone, the total ends in `99`, and the demo payment rule declines it:

```sh
curl -s -X DELETE -o /dev/null "$CF_URL/api/cart" -H "$AUTH"
curl -s -X PUT "$CF_URL/api/cart/items/p-0005" -H "$AUTH" -H 'Content-Type: application/json' -d '{"quantity":1}' | jq
ORDER_ID="$(curl -s -X POST "$CF_URL/api/orders" -H "$AUTH" | jq -r .id)"; echo "$ORDER_ID"
sleep 5
curl -s "$CF_URL/api/orders/$ORDER_ID" -H "$AUTH" | jq -r .status        # PAYMENT_FAILED
curl -s "$CF_URL/api/payments/$ORDER_ID" -H "$AUTH" | jq '{status,reason}'
```

The payment shows `"status": "FAILED"` and `"reason": "card declined (demo rule: totals ending in 99)"`. In the browser, the order page offers **Add these items to your cart again**. Notification sends `Payment for order <id> failed: ...`.

No alarm should fire: a declined card is a normal business outcome, handled successfully by every service.

### 10.3 Direct execute-api call is refused

The raw API Gateway URL skips CloudFront, so it skips WAF and lacks the `X-Origin-Verify` header. The ALB refuses it:

```sh
curl -i "$(tf output -raw api_endpoint)/api/products"     # 403 {"error":"forbidden"}
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"   # 200
```

No alarm should fire: this is a `4xx`, and the 5xx alarms ignore it. API Gateway's access log (`/aws/apigateway/lesson14-dev`) records the `403`.

### 10.4 WAF rate limit

The WAF rate rule blocks any single IP that sends more than 2,000 requests in 5 minutes. To trigger it, send about 3,000 requests to the storefront from your machine.

> [!WARNING]
> This blocks **your IP from the whole site** (storefront and API) for several minutes, until your rate falls below the limit. It costs a fraction of a cent (WAF, CloudFront and S3 requests). A plain loop sends requests one at a time and can take several minutes; WAF can also take a minute or two to start blocking after you pass the limit.

With `hey`, if installed:

```sh
hey -n 3000 -c 20 "$CF_URL/"
```

Without it:

```sh
for i in $(seq 1 3000); do curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/"; done | sort | uniq -c
```

The status summary shows `200` at first and then `403`. Check that you are blocked, and wait until this returns `200` again before you continue:

```sh
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/"
```

The dashboard's **WAF blocked requests** widget (in the Edge row) shows the blocks. With `alarm_email` set, `lesson14-dev-waf-blocked-requests` goes to `ALARM` when more than 100 requests are blocked in 5 minutes. That alarm lives in us-east-1:

```sh
aws cloudwatch describe-alarms --region us-east-1 --alarm-names lesson14-dev-waf-blocked-requests \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
```

### 10.5 One service is down

Stop Product Service the same way as in 10.1:

```sh
SVC=lesson14-dev-product
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$SVC" \
  --min-capacity 0 --max-capacity 4
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" --desired-count 0 --query 'service.desiredCount'
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"
```

Now only the product paths fail. The other services keep working:

```sh
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"                 # 503: no healthy target
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/orders" -H "$AUTH"         # 200
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/cart" -H "$AUTH"           # 200
```

In the browser, `/` still loads but shows an error instead of the products, while `/orders` still lists your orders. Checkout fails too, because Order reads the prices from Product at checkout.

`lesson14-dev-product-under-desired` should go to `ALARM` after 5 minutes (same TODO as in 10.1). If you keep calling the product routes, `lesson14-dev-apigw-5xx-rate` can fire as well (more than 1 % `5xx` for 5 minutes). The ALB 5xx alarm counts only errors returned by targets, so an empty target group does not trigger it.

**Restore** Product Service:

```sh
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount --resource-id "service/$CLUSTER/$SVC" \
  --min-capacity 1 --max-capacity 4
aws ecs update-service --cluster "$CLUSTER" --service "$SVC" --desired-count 1 --query 'service.desiredCount'
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SVC"
curl -s -o /dev/null -w '%{http_code}\n' "$CF_URL/api/products"                 # 200
```

### 10.6 Database fails in one AZ (prose)

There is no demo for this one. The dev stack runs one RDS instance in one AZ (`multi_az = false`) to keep costs down, so an AZ failure would stop `user`, `product`, `order` and `payment` until the instance recovers. Cart keeps working, because DynamoDB already stores data across AZs, and the ECS services and the ALB already span both AZs.

For production, set `multi_az = true` in `dev.tfvars`. RDS then keeps a synchronous standby in the second AZ and fails over to it automatically, at the same DNS name. It doubles the database cost, and changing it on a running instance takes a while. With `single_nat_gateway = false`, each AZ also gets its own NAT gateway, so outbound traffic survives an AZ failure.

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 11. Release v2

Image tags are immutable: a release pushes a new tag and points the stack at it. ECS replaces tasks one at a time (minimum 100 %, maximum 200 % of the desired count), and the circuit breaker rolls back to the last working deployment if the new tasks fail their health checks.

**11.1** Optionally change something in `app/` (run `go -C app test ./...` afterwards). Then build and push `v2`:

```sh
bash scripts/build-push.sh v2
```

**11.2** Set `image_tag = "v2"` in `terraform/environments/dev/dev.tfvars`, then plan, apply and check the rollout:

```sh
tf plan -var-file=dev.tfvars -out=dev.tfplan
tf apply dev.tfplan
bash scripts/check-release.sh v2
```

The plan should only replace the task definitions (the image tag changes), replace `terraform_data.db_init` (so `db-init` runs the new image before the services roll), and update the services that use them. TODO: fill in the counts from the live run. `check-release.sh` fails if any service is not stable, its primary deployment is not `COMPLETED`, or its image is not `:v2`, which is what you see after a rollback.

**11.3** Storefront changes don't need Terraform. Generate and upload again, then invalidate the CloudFront cache so viewers get the new files:

```sh
pnpm --dir storefront generate
aws s3 sync storefront/.output/public "s3://$(tf output -raw storefront_bucket_name)/" --delete
aws cloudfront create-invalidation --distribution-id "$(tf output -raw cloudfront_distribution_id)" --paths "/*"
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 12. Cleanup

**12.1** If a scenario demo left a service paused, restore it first (10.1 or 10.5). Then preview what will be destroyed:

```sh
tf plan -destroy -var-file=dev.tfvars
```

Expect `<N> to destroy` (TODO: fill in from the live run). The list includes the database and the cart table with their data, and every image in ECR.

**12.2** Destroy the stack. Type `yes` when Terraform asks:

```sh
tf destroy -var-file=dev.tfvars
tf state list   # expect no output
```

`force_destroy = true` lets Terraform empty the two S3 buckets and the ECR repositories, the RDS instance goes without a final snapshot, and the secrets are deleted without a recovery window. The RDS instance and the CloudFront distribution take the longest to delete. The state bucket stays, and costs cents per month. Keep it to deploy again later, or remove it in step 13.

**12.3** Optional: check in AWS that the big items are gone. Each command should print an error or nothing:

```sh
aws rds describe-db-instances --db-instance-identifier lesson14-dev
aws ecs describe-clusters --clusters lesson14-dev --query 'clusters[?status==`ACTIVE`].clusterName' --output text
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `lesson14/`)].repositoryName' --output text
aws ec2 describe-nat-gateways --filter Name=tag:Project,Values=lesson14 Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

## 13. Optional: remove the state bucket

> [!CAUTION]
> This permanently deletes every state version in the bucket. Do it only after step 12, when no stack keeps its state in the bucket.

The module sets `prevent_destroy`, so `terraform destroy` refuses to delete the bucket on purpose. Empty the versioned bucket first, then delete it and the local bootstrap state:

```sh
BUCKET="$(terraform -chdir=terraform/bootstrap output -raw state_bucket)"
aws s3api list-object-versions --bucket "$BUCKET" \
  --query '{Objects: [Versions, DeleteMarkers][].{Key:Key,VersionId:VersionId}, Quiet: `true`}' \
  --output json > /tmp/lesson14-state-versions.json
aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/lesson14-state-versions.json
aws s3api delete-bucket --bucket "$BUCKET"
rm terraform/bootstrap/terraform.tfstate*
```

`delete-objects` deletes up to 1,000 versions per call. If the bucket has more, repeat the list and delete commands. If the bucket is already empty, skip `delete-objects`.

The list includes `dev/terraform.tfstate.tflock` entries as well as the state. S3-native locking writes this lock file on every plan and apply and then deletes it, which leaves versions and delete markers behind. A versioned bucket can't be deleted until both are gone, which is why the query lists `Versions` and `DeleteMarkers`.

Check that the bucket is gone. Expect `404 … Not Found`:

```sh
aws s3api head-bucket --bucket "$BUCKET"
rm /tmp/lesson14-state-versions.json
```

<details>
<summary>Sample output</summary>

```text
TODO: paste from live run
```

</details>

To run the lab again, start from step 1. The bucket name is free again, so bootstrap creates the same name.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `aws …` prints nothing, but `aws … \| jq` works | The CLI pager takes over the output | `export AWS_PAGER=""` |
| A script fails with `Set AWS_REGION to the deployed provider region.` | `AWS_REGION` is not exported in this terminal | `export AWS_REGION=ap-southeast-1` |
| `init` doesn't print `configured the backend "s3"`, and `terraform.tfstate` appears in `environments/dev/` | `backend.tf` is missing or renamed, so Terraform uses local state | Restore `backend.tf`, then `tf init -backend-config=dev.backend.hcl -migrate-state` |
| `build-push.sh` fails with `Output "ecr_repository_urls" not found` (or `ecr_repository_urls has no entry for …`) | The repositories (and the dev state) don't exist yet | Run step 5.2 first |
| `docker buildx` fails with `exec format error`, or has no `linux/arm64` platform | No ARM64 emulation on an x86 machine | `docker run --privileged --rm tonistiigi/binfmt --install arm64`, then build again |
| Push fails with `tag invalid … cannot be overwritten because the repository is immutable` | That tag is already in ECR | Use a new tag (`v3`), and set the same `image_tag` |
| Tasks stop with `CannotPullContainerError` | `image_tag` in `dev.tfvars` was never pushed | Push it with `build-push.sh <tag>`, or set the tag you pushed |
| `user`, `product`, `order` or `payment` keep stopping; their log says `password authentication failed` | The roles were changed or dropped after `db-init` ran | Re-run `bash scripts/run-db-init.sh` (step 6.1), then `aws ecs update-service … --force-new-deployment` for that service |
| `apply` fails at `terraform_data.db_init` with `db-init failed: …` | The `db-init` task could not reach RDS, or its image is missing | Read the log lines the script printed, fix, and apply again: the step re-runs |
| `apply` fails with `waiting for ECS Service … to reach steady state` / `circuit breaker` | `wait_for_steady_state` is on: a service whose tasks fail their health checks fails the apply, on the first deploy too | Read the service events and log, push a fixed tag, apply again |
| `check-release.sh` says `primary rollout is FAILED` or the image is the old tag | The circuit breaker rolled the release back | Read the service events (`aws ecs describe-services … --query 'services[0].events[:5]'`) and the service log, fix, push a new tag |
| `seed.sh` or register returns `400` with a password message | The Cognito password policy rejected it | Use 8+ characters with upper case, lower case, a number and a symbol |
| `POST /api/products` returns `400 currency must be VND` | Prices are VND only | Send `"currency": "VND"` |
| `GET /api/products?ids=…` returns `400 too many ids (max 100)` | More than 100 distinct ids in one request | Split the request |
| `build-push.sh` fails with `DRY_RUN must be 1 or unset` | `DRY_RUN` is set to something else (`yes`, `true`, …) | `unset DRY_RUN`, or `DRY_RUN=1` for a dry run |
| The CloudFront URL returns `403` with an XML `AccessDenied` body | The storefront was never uploaded | Step 7 |
| The old storefront still shows after an upload | CloudFront cached the old files | `aws cloudfront create-invalidation … --paths "/*"` (step 11.3) |
| Every request to the site returns `403` | The WAF rate rule blocked your IP (step 10.4) | Wait a few minutes until your request rate falls below the limit |
| Notification log shows `MessageRejected` / `Email address is not verified`, and the notification DLQ fills | SES sandbox: the sender or the customer's address is not verified | Click the SES verification email, and order only as a verified address. Or unset `notify_from_email` for log mode |
| No email arrives, but the log shows `email (log mode, not sent)` | `notify_from_email` is unset, so Notification is in log mode | Expected. Set `notify_from_email` and apply to send real emails |
| A plan after a demo wants to change `aws_appautoscaling_target` | A paused service still has min capacity 0 | Restore min 1, max 4 and desired 1 (10.1 or 10.5), or apply the plan |
| `terraform fmt -check` lists your `*.tfvars` | Your copy isn't formatted | `terraform fmt -recursive terraform` |
| TFLint passes but skips the AWS rules | `--config` is a relative path | Use `--config="$PWD/terraform/.tflint.hcl"` |
