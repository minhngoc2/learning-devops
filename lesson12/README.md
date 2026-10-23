# Lesson 12: Nuxt on private S3 and CloudFront

A static Nuxt site served over HTTPS by CloudFront from a private S3 bucket, deployed by Terraform.

![Nuxt 4](https://img.shields.io/badge/Nuxt-4.6-00DC82?logo=nuxt&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![terraform test 8/8](https://img.shields.io/badge/terraform%20test-8%2F8-brightgreen)
![checkov 22/22](https://img.shields.io/badge/checkov-22%2F22-brightgreen)

> [!NOTE]
> No application server runs in AWS. pnpm generates the static files locally, the AWS CLI uploads them, and Origin Access Control (OAC) lets only CloudFront read the private bucket.

- **[Quickstart](quickstart.md)**: run locally, deploy, publish, verify, cleanup
- [App notes](nuxt-app/README.md) · Modules: [s3-website](terraform/modules/s3-website/README.md) · [cloudfront-spa](terraform/modules/cloudfront-spa/README.md)

## Architecture

**Browser → CloudFront (HTTPS) → Private S3 (via OAC)**

![Nuxt architecture: the visitor browser fetches over HTTPS from CloudFront, which signs requests with OAC to the private S3 bucket; cache and security-headers policies, bucket policy and storage controls; pnpm generate and the AWS CLI publish the files, and Terraform apply creates 9 resources](diagrams/architecture.png)

- **CloudFront:** Redirects HTTP to HTTPS, caches assets, and adds managed security headers.
- **S3:** Private bucket; anonymous requests get `403`. Abandoned multipart uploads expire after 7 days.
- **Caching:** HTML and stable files use `no-cache`; fingerprinted `/_nuxt/` assets are cached for a year as immutable.
- **Routing:** Only `/` maps to `index.html`. Nested page URLs need a CloudFront rewrite.

Diagram source: [`diagrams/source/architecture.json`](diagrams/source/architecture.json) (Archify).

## Results

| Check | Result |
| --- | --- |
| `terraform test` (mocked AWS) | 8 passed |
| TFLint (Terraform + AWS rulesets) | No issues |
| Checkov | 22 passed, 0 failed |
| Apply | 8 added (a fresh apply now creates 9) |
| CloudFront website | Default Nuxt welcome page loaded |
| HTTPS `/` | `200`, HTML, `Cache-Control: no-cache` |
| HTTP `/` | `301` redirect to HTTPS |
| Anonymous S3 access | `403 Forbidden` |

The live rows were recorded on October 20, 2026 (Nuxt 4.6.2, `ap-southeast-1`), before the October 22 Terraform review added the lifecycle rule and security-headers policy. The static checks cover the current code.

> [!TIP]
> Commands, sample output and screenshots are in the [quickstart](quickstart.md).

## Lessons learned

> [!IMPORTANT]
> Upload order matters: fingerprinted assets first, HTML last. Otherwise a visitor can load new HTML that points to assets not uploaded yet.

- **S3 stays private.** OAC signs CloudFront's requests, so the bucket never needs public access.
- **Cache by file type.** Immutable for fingerprinted assets, `no-cache` for HTML and stable files.
- **Static hosting has no router.** Deep links need a CloudFront rewrite to work.

> [!CAUTION]
> AWS resources incur charges until removed. The dev example sets `force_destroy`, so destroying the bucket permanently deletes its contents. Follow the [cleanup steps](quickstart.md#5-cleanup).
