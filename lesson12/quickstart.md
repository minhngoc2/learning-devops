# Quickstart

Run commands from `lesson12/` unless a step explicitly changes directory. Use the same terminal so the deployment variables remain available.

## 1. Prerequisites and local app

- Node.js 22.13+ on the 22.x line, or Node.js 24+, and npm (compatible with the locked Vite and ESLint dependencies).
- Terraform `>= 1.10, < 2.0` and AWS CLI v2 for deployment.
- AWS credentials for the intended account, with permission to manage S3 buckets, bucket settings/policies/objects, CloudFront distributions, OAC, cache policies, and tags. An AWS sandbox account is appropriate for this lab.

```sh
cd app
npm ci
npm run dev
```

Open the URL Vite prints (normally `http://localhost:5173`). Stop the server with Ctrl+C, then return to `lesson12/`:

```sh
cd ..
```

For AWS, configure credentials using your usual profile or SSO flow. If using a named profile, export `AWS_PROFILE` before continuing. Confirm the account:

```sh
aws sts get-caller-identity
```

Deployment creates billable resources. This guide uses local Terraform state; keep the state files until cleanup and do not commit them.

## 2. Validate and create infrastructure

If `terraform/environments/dev/dev.tfvars` does not exist, create it from the example:

```sh
test -f terraform/environments/dev/dev.tfvars || cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

Review that file before applying. Defaults in the example are region `ap-southeast-1`, project `lesson12`, environment `dev`, and **`force_destroy = true`**. This permits destroy to delete all bucket contents; set it to `false` to require an empty bucket instead. The project must be 3–31 lowercase letters/digits/hyphens, start with a letter, and end with a letter or digit. Environments are `dev`, `staging`, or `prod`.

```sh
terraform -chdir=terraform/environments/dev init
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=dev.tfvars
```

The tests use a mocked AWS provider and create no real resources, including the test run that uses `command = apply`. Real `plan`/`apply` require AWS credentials. Terraform installs AWS provider `~> 6.0`; retain and commit the generated `.terraform.lock.hcl` for repeatable provider selection.

Review the plan and confirm the interactive apply prompt. CloudFront provisioning can take several minutes. Terraform outputs the bucket name, distribution ID, website URL, and AWS region. The URL will serve an error until you upload the build.

## 3. Build and publish

```sh
cd app
npm run lint
npm run build
cd ..

BUCKET_NAME="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
DISTRIBUTION_ID="$(terraform -chdir=terraform/environments/dev output -raw distribution_id)"
WEBSITE_URL="$(terraform -chdir=terraform/environments/dev output -raw website_url)"
DEPLOY_REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"
```

Upload hashed assets first, other public files next, and HTML last so the new page references assets already present. Stop if any command fails; do not publish HTML after a failed asset upload.

```sh
aws s3 cp app/dist/assets/ "s3://$BUCKET_NAME/assets/" \
  --recursive --cache-control 'public,max-age=31536000,immutable' \
  --region "$DEPLOY_REGION"

aws s3 cp app/dist/ "s3://$BUCKET_NAME/" \
  --recursive --exclude 'assets/*' --exclude 'index.html' \
  --cache-control 'no-cache' --region "$DEPLOY_REGION"

aws s3 cp app/dist/index.html "s3://$BUCKET_NAME/index.html" \
  --content-type 'text/html' --cache-control 'no-cache' \
  --region "$DEPLOY_REGION"

INVALIDATION_ID="$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" --paths '/*' \
  --query 'Invalidation.Id' --output text)"
aws cloudfront wait invalidation-completed \
  --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
```

Use the same build/upload/invalidation steps for updates. These commands overwrite current files but retain older hashed assets so already-open pages can still fetch them. The upload is not atomic; concurrent deployments need coordination. Avoid immediately deleting old assets on a live site. For this small lab, `cp` deliberately reuploads files so cache metadata is updated even when file contents have not changed; `sync` skips unchanged files. See the AWS CLI references for [copying files](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html) and [sync metadata behavior](https://docs.aws.amazon.com/cli/latest/reference/s3/sync.html).

Only Vite's hashed `assets/` files get immutable caching. Files copied from `public/`, such as `icons.svg`, keep stable names and use `no-cache`. Keep unhashed public files outside `public/assets/` when following this recipe. Do not use public-read ACLs; the bucket enforces ownership and blocks public access.

## 4. Verify and troubleshoot

```sh
printf '%s\n' "$WEBSITE_URL"
curl --fail --head "$WEBSITE_URL/"
curl --head "${WEBSITE_URL/https:/http:}/"
curl --head "https://$BUCKET_NAME.s3.$DEPLOY_REGION.amazonaws.com/index.html"
```

Open the HTTPS URL in a browser and check that the counter works. Expect HTTP `200` and `Cache-Control: no-cache` for the page, an HTTP-to-HTTPS redirect, and `403 AccessDenied` for anonymous direct S3 access. Check a hashed asset URL from `app/dist/index.html` for `public,max-age=31536000,immutable`.

| Symptom | Check |
| --- | --- |
| CloudFront `/` returns 403 | Verify `index.html` exists at the bucket root, the upload succeeded, and apply finished attaching the bucket policy. Complete an invalidation if you visited before uploading. |
| Old page after publishing | Confirm the bucket/distribution outputs match this deployment, inspect object cache headers, and wait for invalidation completion. |
| `/some/route` returns 403 or 404 | Expected: there is no history-route fallback. Use `/` and real object paths until route handling is implemented. |
| Name already exists | Resource names use `<project>-<environment>-<account-id>`. Choose a distinct project/environment for a separate stack; retain the original state for existing resources. |
| Terraform init cannot download the provider | Check network access to the Terraform registry and retry init. |
| Permission denied | Check `AWS_PROFILE`, session expiry, account identity, and the relevant S3/CloudFront IAM permissions. |

## 5. Cleanup

From `lesson12/`, with the same credentials and variable file:

```sh
terraform -chdir=terraform/environments/dev plan -destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev destroy -var-file=dev.tfvars
```

Review the destroy plan before confirming. With `force_destroy = true`, **all uploaded files are permanently deleted**. With `false`, a non-empty bucket prevents deletion; empty that specific lab bucket intentionally or change the setting and apply it before retrying destroy. CloudFront deletion can take several minutes. Do not delete local state as a substitute for destroying resources.
