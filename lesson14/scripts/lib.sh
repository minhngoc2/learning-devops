# shellcheck shell=bash
# Shared prelude for the scripts in this folder. Set fail_prefix, then source this file:
#   set -euo pipefail
#   fail_prefix='seed failed'
#   source "$(dirname "$0")/lib.sh"
# It only defines helpers and lesson_dir; every check runs when the caller invokes it.

: "${fail_prefix:?set fail_prefix before sourcing lib.sh}"
# shellcheck disable=SC2034 # used by the sourcing scripts
lesson_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PAGER=""

fail() { printf '%s: %s\n' "$fail_prefix" "$*" >&2; exit 1; }

# valid_tag "$@": exactly one argument, an ECR image tag (letter, digit or underscore first; at most 128 characters).
valid_tag() { [[ $# -eq 1 && "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; }

require_region() { [[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || fail "$tool is required."
  done
}
