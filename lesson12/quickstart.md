# Quickstart: Nuxt on AWS

Run from `lesson12/` in one terminal. Stop if any command fails.

Requires Node.js 24 LTS, pnpm, Terraform `>= 1.10, < 2.0`, and AWS CLI v2. Use AWS credentials allowed to manage S3 and CloudFront; set `AWS_PROFILE` if needed. AWS resources incur charges.

## 1. Run locally

```sh
pnpm --dir nuxt-app install --frozen-lockfile
pnpm --dir nuxt-app dev
```

Open the printed URL, usually `http://localhost:3000`, and check the default welcome page. Stop with Ctrl+C.

## 2. Create infrastructure

Check the AWS account before making changes:

```sh
aws sts get-caller-identity
```

Already deployed? Reuse its Terraform state and skip to step 3. Otherwise, create the variables file:

```sh
test -f terraform/environments/dev/dev.tfvars || cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

Review `dev.tfvars`. The example uses `ap-southeast-1` and **`force_destroy = true`**, allowing destroy to delete all bucket objects. Names are fixed to `<project>-dev-<account-id>`; for a separate deployment use a distinct `project` and separate state (another checkout, or another `key` in `dev.backend.hcl`).

```sh
terraform -chdir=terraform/environments/dev init
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
tflint --chdir=terraform --init                                               # optional lint; needs TFLint
tflint --chdir=terraform --recursive --config="$PWD/terraform/.tflint.hcl"
uvx checkov --config-file terraform/.checkov.yaml -d terraform                 # optional security scan; needs uv
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=dev.tfvars
```

Tests mock AWS. Expect `Plan: 9 to add`. TFLint must get the config as an absolute path; with `--recursive` it otherwise falls back to default rules in the module folders. Review the plan before confirming apply; CloudFront takes several minutes. State is local in `terraform/environments/dev/` by default; keep it for updates and cleanup. Commit `.terraform.lock.hcl`; exclude state and local tfvars.

### Optional: keep state in S3

Local state is the default. To keep it in the lesson 10–11 state bucket instead (survives a lost laptop, adds locking), that bucket must exist first ([lesson 10–11 quickstart, step 2](../lesson10-11/quickstart.md#2-create-the-state-backend); its own bootstrap state stays local there). Do this before the first `init` to start in S3, or any time later to move existing state. Your AWS identity also needs read/write on the state object and its `.tflock` file. Both copies below are git-ignored:

```sh
cp terraform/environments/dev/backend.tf.example terraform/environments/dev/backend.tf
cp terraform/environments/dev/dev.backend.hcl.example terraform/environments/dev/dev.backend.hcl   # set bucket and region to the bootstrap's
terraform -chdir=../lesson10-11/terraform/bootstrap output -raw state_bucket   # the bucket name
terraform -chdir=terraform/environments/dev init -backend-config=dev.backend.hcl -migrate-state   # copies existing local state, if any
```

Before running `init`, confirm `key` in `dev.backend.hcl` is `lesson12/dev/terraform.tfstate`. When Terraform asks to copy the existing state, answer `yes`: answering no, or leaving out `-migrate-state`, starts with empty state, and the next apply fails on names that already exist. Keep the old `terraform.tfstate` and `terraform.tfstate.backup` until `terraform state list` shows the expected resources, then delete both. From then on, always run `init` with `-backend-config=dev.backend.hcl`; plain `init` on a fresh checkout fails with "key is required".

## 3. Generate and publish

Confirm the destination; uploads overwrite matching files:

```sh
terraform -chdir=terraform/environments/dev output
```

Run the whole block. It stops on failure and uploads HTML after its dependencies:

```sh
(
  set -eu

  pnpm --dir nuxt-app generate
  test -s nuxt-app/.output/public/index.html
  test -d nuxt-app/.output/public/_nuxt

  BUCKET_NAME="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
  DISTRIBUTION_ID="$(terraform -chdir=terraform/environments/dev output -raw distribution_id)"
  WEBSITE_URL="$(terraform -chdir=terraform/environments/dev output -raw website_url)"
  DEPLOY_REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"
  printf 'Publishing to %s (%s)\n' "$BUCKET_NAME" "$WEBSITE_URL"

  # Nuxt-generated assets first; latest.json has a stable URL.
  aws s3 cp nuxt-app/.output/public/_nuxt/ "s3://$BUCKET_NAME/_nuxt/" \
    --recursive --exclude 'builds/latest.json' \
    --cache-control 'public,max-age=31536000,immutable' \
    --region "$DEPLOY_REGION"

  # Payloads and stable public files require revalidation.
  aws s3 cp nuxt-app/.output/public/ "s3://$BUCKET_NAME/" \
    --recursive --exclude '_nuxt/*' --include '_nuxt/builds/latest.json' \
    --exclude '*.html' \
    --cache-control 'no-cache' --region "$DEPLOY_REGION"

  # HTML last, after its dependencies have uploaded successfully.
  aws s3 cp nuxt-app/.output/public/ "s3://$BUCKET_NAME/" \
    --recursive --exclude '*' --include '*.html' \
    --content-type 'text/html' --cache-control 'no-cache' \
    --region "$DEPLOY_REGION"

  INVALIDATION_ID="$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" --paths '/*' \
    --query 'Invalidation.Id' --output text)"
  aws cloudfront wait invalidation-completed \
    --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"

  printf 'Website: %s\n' "$WEBSITE_URL"
)
```

Don't add files under `nuxt-app/public/_nuxt/`; that path is reserved for assets Nuxt generates. Stable files require revalidation; fingerprinted assets use one-year immutable caching. Retain older assets for open tabs. Uploads are not atomic; avoid concurrent releases.

## 4. Verify

```sh
BUCKET_NAME="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
WEBSITE_URL="$(terraform -chdir=terraform/environments/dev output -raw website_url)"
DEPLOY_REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"

printf '%s\n' "$WEBSITE_URL"
curl --fail --head "$WEBSITE_URL/"
curl --head "${WEBSITE_URL/https:/http:}/"
curl --head "https://$BUCKET_NAME.s3.$DEPLOY_REGION.amazonaws.com/index.html"
```

Expect HTTPS `200` with `Cache-Control: no-cache` and security headers such as `strict-transport-security`, HTTP `301` to HTTPS, and anonymous S3 `403`. Open the CloudFront URL to check the Nuxt welcome page. Inspect a generated JS/CSS response under `/_nuxt/` for `public,max-age=31536000,immutable`.

<details>
<summary>Sample output (October 20, 2026, before the October 22 review)</summary>

| Check | Result |
| --- | --- |
| Terraform apply | 8 added, 0 changed, 0 destroyed |
| HTTPS `/` | `200`, HTML, `Cache-Control: no-cache` |
| HTTP `/` | `301` redirect to HTTPS |
| Anonymous S3 access | `403 Forbidden` |

The Nuxt welcome page served through CloudFront:

![Nuxt welcome page served through CloudFront](evidence/website.png)

The CloudFront distribution with its S3 origin (identifiers masked):

![CloudFront distribution with an S3 origin; identifiers masked](evidence/cloudfront-redacted.png)

The generated Nuxt files in S3 (bucket name masked):

![Generated Nuxt files in S3; bucket name masked](evidence/s3-objects-redacted.png)

</details>

For errors or nested routes, see [troubleshooting](nuxt-app/README.md#troubleshooting). If you have the local guide (`docs/`, git-ignored), its chapter 8 diagnoses failures layer by layer.

## 5. Cleanup

Remove the infrastructure and hosted site:

```sh
terraform -chdir=terraform/environments/dev plan -destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev destroy -var-file=dev.tfvars
```

> [!CAUTION]
> Review before confirming. **`force_destroy = true` permanently deletes every bucket object.** With `false`, empty the intended bucket first.

Retain state until destroy completes; deleting local state does not remove AWS resources.
