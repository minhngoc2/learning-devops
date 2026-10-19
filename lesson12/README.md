# Lesson 12: React on private S3 and CloudFront

Deploy a React/Vite static app to a private S3 bucket and serve it through CloudFront over HTTPS. Terraform provisions the infrastructure; the AWS CLI publishes the build. CloudFront uses Origin Access Control (OAC) to read S3 objects without making the bucket public.

**Start here:** [Quickstart](quickstart.md) — prerequisites, local development, deployment, uploads, verification, and cleanup.

## Project

`Browser → CloudFront (HTTPS) → private S3 bucket (signed OAC requests)`

| Component | Purpose |
| --- | --- |
| [React/Vite app](app/README.md) | Static demo with an interactive counter |
| [Dev environment](terraform/environments/dev/main.tf) | Composes the modules and restricts bucket reads to its CloudFront distribution |
| [S3 module](terraform/modules/s3-website/README.md) | Private, encrypted bucket with public access blocked |
| [CloudFront module](terraform/modules/cloudfront-spa/README.md) | HTTPS delivery, OAC, and cache policy |

This lab uses the generated CloudFront hostname, local Terraform state, and manual uploads. It has no custom domain, CI/CD, or browser-history route fallback; `/` serves `index.html`.

## Result and evidence

Deployment evidence captured on **19 October 2026**:

- **Website:** [Open the deployed app](https://d2w09l92ojbxvw.cloudfront.net). The browser screenshot shows the page loaded and the counter at `6`.
- **S3:** The uploaded build includes `assets/`, `favicon.svg`, `icons.svg`, and `index.html`.
- **CloudFront:** The distribution shows the generated domain and an S3 origin.
- **Infrastructure:** The submitted apply completed successfully in `ap-southeast-1`: **8 resources added, 0 changed, 0 destroyed**. CloudFront creation took about 2 minutes 39 seconds.
- **Validation:** The submitted format check completed without errors. All three Terraform tests passed: `private_bucket`, `https_spa`, and `bucket_policy`.

Apply output excerpt with identifying values replaced by placeholders:

```text
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

aws_region = "ap-southeast-1"
bucket_name = "lesson12-dev-<AWS_ACCOUNT_ID>"
distribution_id = "<DISTRIBUTION_ID>"
website_url = "https://<CLOUDFRONT_DOMAIN>"
```

The eight resources cover the S3 bucket, ownership controls, public-access block, encryption, bucket policy, CloudFront distribution, OAC, and cache policy. The Terraform tests use a mocked AWS provider; the apply log and screenshots provide deployment evidence.

Account-identifying bucket names, the ARN, and internal resource IDs are masked in the console images. The public website link above is intentionally visible; availability depends on the lab remaining deployed.

![Deployed React/Vite page through CloudFront, with the counter at 6](evidence/website.png)

![S3 objects showing the uploaded build; bucket name redacted](evidence/s3-objects-redacted.png)

![CloudFront distribution with an S3 origin; internal identifiers redacted](evidence/cloudfront-redacted.png)

See the [cleanup steps](quickstart.md#5-cleanup) when finished. Resources can incur charges; the example enables `force_destroy`, which allows bucket deletion to remove all uploaded objects.
