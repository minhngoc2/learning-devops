#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'Release check failed: %s\n' "$*" >&2; exit 1; }

[[ $# -ge 1 && $# -le 2 && "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail 'Usage: bash scripts/check-release.sh <expected-image-tag> [dev|staging]'
environment=${2:-dev}
[[ "$environment" == dev || "$environment" == staging ]] || fail 'Environment must be dev or staging.'
[[ -n "${AWS_REGION:-}" ]] || fail 'Set AWS_REGION to the deployed provider region.'
for tool in terraform aws curl; do
  command -v "$tool" >/dev/null || fail "$tool is required."
done
export AWS_PAGER=""

lesson_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$lesson_dir/terraform/environments/$environment"
cluster=$(terraform output -raw cluster_name)
service=$(terraform output -raw service_name)
repo=$(terraform output -raw ecr_repository_url)
[[ -n "$cluster" && "$cluster" != None && -n "$service" && "$service" != None ]] || fail "Missing cluster/service outputs; initialize the existing $environment backend first."
expected_image="$repo:$1"
repo_account=${repo%%.*}
[[ "$repo_account" =~ ^[0-9]{12}$ ]] || fail 'Expected a private ECR repository URL in the Terraform output.'
account=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text)
[[ "$account" == "$repo_account" ]] || fail 'AWS identity is not in the account of this lab ECR repository.'

printf 'Waiting for %s/%s; expected image %s\n' "$cluster" "$service" "$expected_image" >&2
aws ecs wait services-stable --region "$AWS_REGION" --cluster "$cluster" --services "$service"
definition=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$cluster" --services "$service" \
  --query 'services[0].taskDefinition' --output text)
[[ -n "$definition" && "$definition" != None ]] || fail 'The service has no task definition.'
rollout=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$cluster" --services "$service" \
  --query "services[0].deployments[?status=='PRIMARY'].rolloutState | [0]" --output text)
[[ "$rollout" == COMPLETED ]] || fail "Primary rollout is $rollout; inspect service events."
image=$(aws ecs describe-task-definition --region "$AWS_REGION" --task-definition "$definition" \
  --query "taskDefinition.containerDefinitions[?name=='api'].image | [0]" --output text)
[[ "$image" == "$expected_image" ]] || fail "Service image is $image, expected $expected_image; the release may have rolled back."

task_list=$(aws ecs list-tasks --region "$AWS_REGION" --cluster "$cluster" --service-name "$service" \
  --desired-status RUNNING --query taskArns --output text)
[[ -n "$task_list" && "$task_list" != None ]] || fail 'No task candidates were returned.'
read -r -a task_arns <<< "${task_list//$'\n'/ }"
# shortcut: one describe-tasks call accepts at most 100 ARNs; batch requests before reusing this helper for larger services.
task=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "${task_arns[@]}" \
  --query "tasks[?taskDefinitionArn=='$definition' && lastStatus=='RUNNING' && healthStatus=='HEALTHY'].taskArn | [0]" --output text)
[[ -n "$task" && "$task" != None ]] || fail 'No healthy running task matches the current service definition.'
if [[ "$environment" == staging ]]; then
  url=$(terraform output -raw api_url)
  target_group=$(terraform output -raw target_group_arn)
  [[ "$url" =~ ^http://[a-zA-Z0-9.-]+\.elb\.amazonaws\.com$ ]] || fail 'Expected the staging HTTP ALB URL.'
  [[ -n "$target_group" && "$target_group" != None ]] || fail 'Missing staging target group.'
  ip=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
    --query "tasks[0].attachments[?type=='ElasticNetworkInterface'].details[] | [?name=='privateIPv4Address'].value | [0]" --output text)
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'The selected task has no private IPv4 target.'
  aws elbv2 wait target-in-service --region "$AWS_REGION" --target-group-arn "$target_group" --targets "Id=$ip,Port=8080"
else
  eni=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$cluster" --tasks "$task" \
    --query "tasks[0].attachments[?type=='ElasticNetworkInterface'].details[] | [?name=='networkInterfaceId'].value | [0]" --output text)
  [[ -n "$eni" && "$eni" != None ]] || fail 'The selected task has no ENI; it may have stopped.'
  ip=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" --network-interface-ids "$eni" \
    --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'No public IPv4 address for the dev task.'
  url="http://$ip:8080"
fi
health=$(curl --silent --show-error --fail-with-body --connect-timeout 5 --max-time 10 "$url/health")
[[ "$health" == '{"status":"ok"}' ]] || fail "Unexpected /health response at $url."
ready=$(curl --silent --show-error --fail-with-body --connect-timeout 5 --max-time 10 "$url/ready")
[[ "$ready" == '{"status":"ready"}' ]] || fail "Unexpected /ready response at $url."
printf 'Verified task %s on %s; HTTP liveness and DB readiness passed.\n' "$task" "$definition" >&2
printf '%s\n' "$url"
