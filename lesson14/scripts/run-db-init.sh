#!/usr/bin/env bash
# Run the one-off db-init task (schemas, roles, grants), wait for it, and fail unless it exited 0.
# Usage: AWS_REGION=<region> bash scripts/run-db-init.sh
set -euo pipefail

fail() { printf 'db-init failed: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || fail 'Usage: bash scripts/run-db-init.sh'
[[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'
for tool in terraform aws; do
  command -v "$tool" >/dev/null || fail "$tool is required."
done
export AWS_PAGER=""

lesson_dir="$(cd "$(dirname "$0")/.." && pwd)"
dev_root="$lesson_dir/terraform/environments/dev"
cluster=$(terraform -chdir="$dev_root" output -raw cluster_name)
run_command=$(terraform -chdir="$dev_root" output -raw db_init_run_command)
[[ "$run_command" == "aws ecs run-task "* ]] || fail 'Unexpected db_init_run_command output.'

# The command string comes from our own Terraform output (it carries quoted network configuration).
task=$(eval "$run_command --query 'tasks[0].taskArn' --output text")
[[ -n "$task" && "$task" != None ]] || fail 'run-task started no task; check the capacity and subnets.'
printf 'Started %s; waiting for it to stop\n' "$task" >&2

aws ecs wait tasks-stopped --region "$AWS_REGION" --cluster "$cluster" --tasks "$task"
exit_code=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
  --query "tasks[0].containers[?name=='app'].exitCode | [0]" --output text)
reason=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
  --query 'tasks[0].stoppedReason' --output text)

printf 'Last log events from /ecs/lesson14-dev-db-init:\n' >&2
aws logs tail /ecs/lesson14-dev-db-init --region "$AWS_REGION" --since 10m --format short | tail -n 20 >&2 || true

[[ "$exit_code" == 0 ]] || fail "container app exited with $exit_code ($reason)."
printf 'db-init completed (exit 0).\n' >&2
