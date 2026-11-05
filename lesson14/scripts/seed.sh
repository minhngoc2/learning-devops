#!/usr/bin/env bash
# Upload product images and create the six seed products through the public API.
# Usage: AWS_REGION=<region> bash scripts/seed.sh <cloudfront_url> <email> <password>
# Re-running is safe: an existing account (409) is reused and existing product ids (409) are skipped.
set -euo pipefail

fail_prefix='seed failed'
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[[ $# -eq 3 && "$1" =~ ^https://[A-Za-z0-9.-]+$ ]] || fail 'Usage: bash scripts/seed.sh <cloudfront_url (https://..., no trailing slash)> <email> <password>'
base_url=$1 email=$2 password=$3
require_region
require_tools terraform aws curl python3

bucket=$(terraform -chdir="$lesson_dir/terraform/environments/dev" output -raw images_bucket_name)
[[ -n "$bucket" ]] || fail 'Missing images_bucket_name output; apply the dev root first.'

aws s3 cp "$lesson_dir/seed/images/" "s3://$bucket/products/" --recursive \
  --content-type image/png --region "$AWS_REGION" >&2

# The password and the token never reach a command line (ps): python reads the credentials from its
# environment, curl reads the body from stdin and the Authorization header from a private temp file.
credentials_json() {
  SEED_EMAIL=$email SEED_PASSWORD=$password SEED_NAME=${1:-} python3 -c '
import json, os
body = {"email": os.environ["SEED_EMAIL"], "password": os.environ["SEED_PASSWORD"]}
if os.environ["SEED_NAME"]:
    body["display_name"] = os.environ["SEED_NAME"]
print(json.dumps(body))'
}
body_file=$(mktemp)
header_file=$(mktemp)
trap 'rm -f "$body_file" "$header_file"' EXIT

# post <path> <json> [auth] → prints the HTTP status; the body lands in $body_file.
# With auth, the header comes from $header_file.
post() {
  local auth=()
  [[ -n "${3:-}" ]] && auth=(-H "@$header_file")
  curl -sS -o "$body_file" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    ${auth[@]+"${auth[@]}"} --data @- "$base_url$1" <<< "$2"
}

status=$(post /api/users/register "$(credentials_json "Seed admin")")
case "$status" in
  201) printf 'Registered %s\n' "$email" >&2 ;;
  409) printf '%s already registered; logging in\n' "$email" >&2 ;;
  *) fail "register returned $status: $(cat "$body_file")" ;;
esac

status=$(post /api/users/login "$(credentials_json)")
[[ "$status" == 200 ]] || fail "login returned $status: $(cat "$body_file")"
token=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id_token"])' "$body_file")
printf 'Authorization: Bearer %s\n' "$token" > "$header_file"

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
  status=$(post /api/products "$body" auth)
  case "$status" in
    201) printf '%s\n' "$id" ;;
    409) printf '%s (already exists)\n' "$id" ;;
    *) fail "POST /api/products for $id returned $status: $(cat "$body_file")" ;;
  esac
done <<< "$bodies"
