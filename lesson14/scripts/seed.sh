#!/usr/bin/env bash
# Upload product images and create the six seed products through the public API.
# Usage: AWS_REGION=<region> bash scripts/seed.sh <cloudfront_url> <email> <password>
# Re-running is safe: an existing account (409) is reused and existing product ids (409) are skipped.
set -euo pipefail

fail() { printf 'seed failed: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 3 && "$1" =~ ^https://[A-Za-z0-9.-]+$ ]] || fail 'Usage: bash scripts/seed.sh <cloudfront_url (https://..., no trailing slash)> <email> <password>'
base_url=$1 email=$2 password=$3
[[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'
for tool in terraform aws curl python3; do
  command -v "$tool" >/dev/null || fail "$tool is required."
done
export AWS_PAGER=""

lesson_dir="$(cd "$(dirname "$0")/.." && pwd)"
bucket=$(terraform -chdir="$lesson_dir/terraform/environments/dev" output -raw images_bucket_name)
[[ -n "$bucket" ]] || fail 'Missing images_bucket_name output; apply the dev root first.'

aws s3 cp "$lesson_dir/seed/images/" "s3://$bucket/products/" --recursive \
  --content-type image/png --region "$AWS_REGION" >&2

json() { python3 -c 'import json,sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))' "$@"; }
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

# post <path> <json> [token] → prints the HTTP status; the body lands in $body_file.
post() {
  local auth=()
  [[ -n "${3:-}" ]] && auth=(-H "Authorization: Bearer $3")
  curl -sS -o "$body_file" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    ${auth[@]+"${auth[@]}"} --data "$2" "$base_url$1"
}

status=$(post /api/users/register "$(json email "$email" password "$password" display_name "Seed admin")")
case "$status" in
  201) printf 'Registered %s\n' "$email" >&2 ;;
  409) printf '%s already registered; logging in\n' "$email" >&2 ;;
  *) fail "register returned $status: $(cat "$body_file")" ;;
esac

status=$(post /api/users/login "$(json email "$email" password "$password")")
[[ "$status" == 200 ]] || fail "login returned $status: $(cat "$body_file")"
token=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id_token"])' "$body_file")

# One compact JSON body per line: the products.json entry with image → image_key "products/<file>".
bodies=$(python3 - "$lesson_dir/seed/products.json" <<'PY'
import json, sys
for p in json.load(open(sys.argv[1], encoding="utf-8")):
    p["image_key"] = "products/" + p.pop("image")
    print(json.dumps(p, ensure_ascii=False))
PY
)

while IFS= read -r body; do
  id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$body")
  status=$(post /api/products "$body" "$token")
  case "$status" in
    201) printf '%s\n' "$id" ;;
    409) printf '%s (already exists)\n' "$id" ;;
    *) fail "POST /api/products for $id returned $status: $(cat "$body_file")" ;;
  esac
done <<< "$bodies"
