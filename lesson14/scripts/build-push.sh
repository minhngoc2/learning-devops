#!/usr/bin/env bash
# Build and push all seven images (six services + db-init) for linux/arm64.
# Usage: AWS_REGION=<region> bash scripts/build-push.sh <tag>
# DRY_RUN=1 prints the docker commands instead of running them; it skips Terraform, the ECR login
# and docker entirely, using placeholder repository URLs, so it needs no AWS access or state.
set -euo pipefail

fail() { printf 'build-push failed: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 && "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail 'Usage: bash scripts/build-push.sh <image-tag>'
tag=$1
dry_run=${DRY_RUN:-0}
if [[ "$dry_run" == 1 ]]; then
  region=${AWS_REGION:-ap-southeast-1}
else
  [[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'
  region=$AWS_REGION
  for tool in terraform aws docker python3; do
    command -v "$tool" >/dev/null || fail "$tool is required."
  done
fi
export AWS_PAGER=""

lesson_dir="$(cd "$(dirname "$0")/.." && pwd)"
names=(user product cart order payment notification db-init)

# urls[i] is the repository URL of names[i] (indexed arrays keep macOS bash 3.2 working).
urls=()
if [[ "$dry_run" == 1 ]]; then
  for name in "${names[@]}"; do
    urls+=("123456789012.dkr.ecr.$region.amazonaws.com/lesson14/$name")
  done
else
  outputs=$(terraform -chdir="$lesson_dir/terraform/environments/dev" output -json ecr_repository_urls)
  for name in "${names[@]}"; do
    url=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$outputs" "$name")
    [[ -n "$url" ]] || fail "ecr_repository_urls has no entry for $name; apply the dev root first."
    urls+=("$url")
  done
  registry=${urls[0]%%/*}
  aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry" >&2
fi

for i in "${!names[@]}"; do
  name=${names[$i]}
  cmd=(docker buildx build --platform linux/arm64 --build-arg "SERVICE=$name"
    -t "${urls[$i]}:$tag" --push "$lesson_dir/app")
  if [[ "$dry_run" == 1 ]]; then
    printf '%q ' "${cmd[@]}"
    printf '\n'
  else
    printf 'Building %s\n' "$name" >&2
    "${cmd[@]}"
  fi
done

printf '\n%-14s %s\n' IMAGE URI
for i in "${!names[@]}"; do
  printf '%-14s %s\n' "${names[$i]}" "${urls[$i]}:$tag"
done
