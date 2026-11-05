#!/usr/bin/env bash
# Verify a release: every service is stable on <tag>, the API answers through CloudFront, and the
# raw execute-api URL is refused (403, origin verification). Prints only the CloudFront URL.
set -euo pipefail

fail_prefix='Release check failed'
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

valid_tag "$@" || fail 'Usage: bash scripts/check-release.sh <expected-image-tag>'
tag=$1
require_region
require_tools terraform aws curl python3

dev_root="$lesson_dir/terraform/environments/dev"
services=(user product cart order payment notification)

cluster=$(terraform -chdir="$dev_root" output -raw cluster_name)
cloudfront_url=$(terraform -chdir="$dev_root" output -raw cloudfront_url)
api_endpoint=$(terraform -chdir="$dev_root" output -raw api_endpoint)
service_names=$(terraform -chdir="$dev_root" output -json service_names)
repo_urls=$(terraform -chdir="$dev_root" output -json ecr_repository_urls)
[[ -n "$cluster" && "$cluster" != None ]] || fail 'Missing cluster_name output; initialize the dev backend first.'
[[ "$cloudfront_url" =~ ^https://[a-z0-9]+\.cloudfront\.net$ ]] || fail "Expected a CloudFront URL, got '$cloudfront_url'."
[[ "$api_endpoint" =~ ^https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com ]] || fail "Expected an execute-api URL, got '$api_endpoint'."

lookup() { python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$1" "$2"; }

for svc in "${services[@]}"; do
  service=$(lookup "$service_names" "$svc")
  repo=$(lookup "$repo_urls" "$svc")
  [[ -n "$service" && -n "$repo" ]] || fail "Missing service_names/ecr_repository_urls entry for $svc."
  expected_image="$repo:$tag"
  printf 'Waiting for %s/%s; expected image %s\n' "$cluster" "$service" "$expected_image" >&2
  aws ecs wait services-stable --region "$AWS_REGION" --cluster "$cluster" --services "$service" \
    || fail "$service did not become stable."
  rollout=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$cluster" --services "$service" \
    --query "services[0].deployments[?status=='PRIMARY'].rolloutState | [0]" --output text)
  [[ "$rollout" == COMPLETED ]] || fail "$service primary rollout is $rollout; inspect service events."
  definition=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$cluster" --services "$service" \
    --query "services[0].deployments[?status=='PRIMARY'].taskDefinition | [0]" --output text)
  [[ -n "$definition" && "$definition" != None ]] || fail "$service has no primary task definition."
  image=$(aws ecs describe-task-definition --region "$AWS_REGION" --task-definition "$definition" \
    --query "taskDefinition.containerDefinitions[?name=='app'].image | [0]" --output text)
  [[ "$image" == "$expected_image" ]] || fail "$service image is $image, expected $expected_image; the release may have rolled back."
done

public=$(curl --fail-with-body -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
  "$cloudfront_url/api/products") || fail "GET $cloudfront_url/api/products failed."
[[ "$public" == 200 ]] || fail "GET $cloudfront_url/api/products returned $public, expected 200."
direct=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 "$api_endpoint/api/products" || true)
[[ "$direct" == 403 ]] || fail "Direct execute-api request returned $direct, expected 403 (origin verification)."

printf 'All %d services run %s; CloudFront serves the API; direct execute-api is refused.\n' "${#services[@]}" "$tag" >&2
printf '%s\n' "$cloudfront_url"
