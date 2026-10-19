# Quickstart

Run from `lesson12/` in one terminal. Stop if any command fails.

Requires Node.js 22.13+ on the 22.x line or Node.js 24+, npm, Terraform `>= 1.10, < 2.0`, and AWS CLI v2. Use AWS credentials allowed to manage S3, CloudFront, OAC, cache policies, and tags; export `AWS_PROFILE` first if needed.

AWS resources incur charges. Terraform state stays local: retain it for updates and cleanup, and keep it out of Git.

## 1. Run locally

```sh
npm --prefix app ci
npm --prefix app run dev
```

Open the printed URL, usually `http://localhost:5173`. Stop with Ctrl+C before continuing.

## 2. Create infrastructure

```sh
aws sts get-caller-identity
test -f terraform/environments/dev/dev.tfvars || cp terraform/environments/dev/dev.tfvars.example terraform/environments/dev/dev.tfvars
```

Review `dev.tfvars`: the example uses `ap-southeast-1`, project `lesson12`, environment `dev`, and **`force_destroy = true`**, allowing destroy to delete every bucket object. Set it to `false` to require an empty bucket. Use a distinct project/environment for a separate deployment.

```sh
terraform -chdir=terraform/environments/dev init
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=dev.tfvars
```

Tests mock AWS and create no resources. Review the real plan before confirming apply; CloudFront takes several minutes. Keep `.terraform.lock.hcl` in Git. The website serves errors until the build is uploaded.

## 3. Build and publish

```sh
npm --prefix app run lint
npm --prefix app run build

BUCKET_NAME="$(terraform -chdir=terraform/environments/dev output -raw bucket_name)"
DISTRIBUTION_ID="$(terraform -chdir=terraform/environments/dev output -raw distribution_id)"
WEBSITE_URL="$(terraform -chdir=terraform/environments/dev output -raw website_url)"
DEPLOY_REGION="$(terraform -chdir=terraform/environments/dev output -raw aws_region)"
```

Upload hashed assets first, stable public files second, and HTML last. **Do not publish HTML after a failed upload.**

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

Repeat these steps for updates. Uploads overwrite current files but retain old hashed assets for open pages; coordinate releases because uploads are not atomic. `cp` reapplies cache metadata even for unchanged files. Keep unhashed public files outside `public/assets/`; do not use public-read ACLs.

## 4. Verify

```sh
printf '%s\n' "$WEBSITE_URL"
curl --fail --head "$WEBSITE_URL/"
curl --head "${WEBSITE_URL/https:/http:}/"
curl --head "https://$BUCKET_NAME.s3.$DEPLOY_REGION.amazonaws.com/index.html"
```

Expect HTTPS `200` with `Cache-Control: no-cache`, an HTTP-to-HTTPS redirect, and anonymous S3 `403 AccessDenied`. Open the website and test the counter; inspect a hashed asset URL for `public,max-age=31536000,immutable`.

| Problem | Check |
| --- | --- |
| CloudFront `/` returns 403 | Upload root `index.html`, confirm apply attached the bucket policy, then invalidate if you visited before uploading. |
| Old content | Check the deployment outputs and cache headers; wait for invalidation completion. |
| Other routes return 403/404 | Expected: only `/` maps to `index.html`; there is no browser-history fallback. |
| AWS access denied | Check the profile, account, session expiry, and required S3/CloudFront permissions. |

## 5. Cleanup

```sh
terraform -chdir=terraform/environments/dev plan -destroy -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev destroy -var-file=dev.tfvars
```

Review before confirming: **`force_destroy = true` permanently deletes all bucket contents**. With `false`, empty the intended lab bucket before destroy. Wait for CloudFront deletion; deleting local state does not remove AWS resources.
