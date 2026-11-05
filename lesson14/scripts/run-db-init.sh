#!/usr/bin/env bash
# Run the one-off db-init task (schemas, roles, grants), wait for it, and fail unless it exited 0.
# terraform apply runs it through terraform_data.db_init, passing the DB_INIT_* variables because the outputs
# don't exist yet. By hand (a re-run), leave them unset: they are read from the dev root's outputs.
# Usage: AWS_REGION=<region> bash scripts/run-db-init.sh
#   optional: DB_INIT_TASK_DEFINITION, DB_INIT_CLUSTER, DB_INIT_SUBNETS (comma-joined),
#             DB_INIT_SECURITY_GROUP, DB_INIT_LOG_GROUP
set -euo pipefail

fail() { printf 'db-init failed: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || fail 'Usage: bash scripts/run-db-init.sh'
[[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'
command -v aws >/dev/null || fail 'aws is required.'
export AWS_PAGER=""

lesson_dir="$(cd "$(dirname "$0")/.." && pwd)"
dev_root="$lesson_dir/terraform/environments/dev"

tf_output() {
  command -v terraform >/dev/null || fail "terraform is required to read the $1 output (or set the DB_INIT_* variables)."
  terraform -chdir="$dev_root" output -raw "$1"
}

if [[ -n "${DB_INIT_TASK_DEFINITION:-}" ]]; then
  task_definition=$DB_INIT_TASK_DEFINITION
  cluster=${DB_INIT_CLUSTER:?set DB_INIT_CLUSTER together with DB_INIT_TASK_DEFINITION}
  subnets=${DB_INIT_SUBNETS:?set DB_INIT_SUBNETS together with DB_INIT_TASK_DEFINITION}
  security_group=${DB_INIT_SECURITY_GROUP:?set DB_INIT_SECURITY_GROUP together with DB_INIT_TASK_DEFINITION}
  log_group=${DB_INIT_LOG_GROUP:?set DB_INIT_LOG_GROUP together with DB_INIT_TASK_DEFINITION}
else
  cluster=$(tf_output cluster_name)
  log_group=$(tf_output db_init_log_group_name)
  run_command=$(tf_output db_init_run_command)
  # Pull the pieces out of the output instead of eval-ing it.
  task_definition_re='--task-definition ([^ ]+)'
  network_re='subnets=\[([^]]+)\],securityGroups=\[([^]]+)\]'
  [[ "$run_command" =~ $task_definition_re ]] || fail 'Unexpected db_init_run_command output (task definition).'
  task_definition=${BASH_REMATCH[1]}
  [[ "$run_command" =~ $network_re ]] || fail 'Unexpected db_init_run_command output (network).'
  subnets=${BASH_REMATCH[1]}
  security_group=${BASH_REMATCH[2]}
fi

id_list='^[A-Za-z0-9-]+(,[A-Za-z0-9-]+)*$'
[[ "$task_definition" =~ ^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:task-definition/[A-Za-z0-9_-]+:[0-9]+$ ]] \
  || fail "Unexpected task definition '$task_definition'."
[[ "$cluster" =~ ^[A-Za-z0-9_-]+$ ]] || fail "Unexpected cluster '$cluster'."
[[ "$subnets" =~ $id_list ]] || fail "Unexpected subnets '$subnets'."
[[ "$security_group" =~ ^sg-[a-f0-9]+$ ]] || fail "Unexpected security group '$security_group'."
[[ "$log_group" =~ ^/[A-Za-z0-9_./-]+$ ]] || fail "Unexpected log group '$log_group'."

task=$(aws ecs run-task --region "$AWS_REGION" --cluster "$cluster" --launch-type FARGATE \
  --task-definition "$task_definition" \
  --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_group],assignPublicIp=DISABLED}" \
  --query 'tasks[0].taskArn' --output text)
[[ -n "$task" && "$task" != None ]] || fail 'run-task started no task; check the capacity and subnets.'
printf 'Started %s; waiting for it to stop\n' "$task" >&2

aws ecs wait tasks-stopped --region "$AWS_REGION" --cluster "$cluster" --tasks "$task"
exit_code=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
  --query "tasks[0].containers[?name=='app'].exitCode | [0]" --output text)
reason=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
  --query 'tasks[0].stoppedReason' --output text)

printf 'Last log events from %s:\n' "$log_group" >&2
aws logs tail "$log_group" --region "$AWS_REGION" --since 10m --format short | tail -n 20 >&2 || true

[[ "$exit_code" == 0 ]] || fail "container app exited with $exit_code ($reason)."
printf 'db-init completed (exit 0).\n' >&2
