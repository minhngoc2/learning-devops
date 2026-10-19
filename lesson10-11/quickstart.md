# Quickstart

From `lesson10-11/`, use one terminal; stop on failures.

Requires Docker Compose with ARM64 builds, Terraform `>= 1.10, < 2.0`, and AWS CLI v2 with lab permissions. Set `AWS_PROFILE` if needed. AWS resources incur charges.

## 1. Run locally

```bash
docker compose -f app/compose.yaml up -d --build
curl --fail-with-body http://localhost:8080/ready
curl --fail-with-body -X POST http://localhost:8080/todos \
  -H 'Content-Type: application/json' -d '{"title":"hello locally"}'
curl --fail-with-body http://localhost:8080/todos
```

Retry `/ready` during startup. Stop: `docker compose -f app/compose.yaml down`.

## 2. Create the state backend

Reuse existing bootstrap state/backend files. Review plans before applying.

```bash
export LESSON_DIR="$PWD"
export AWS_REGION=ap-southeast-1
aws sts get-caller-identity

cd "$LESSON_DIR/terraform/bootstrap"
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output -raw state_bucket

cd "$LESSON_DIR/terraform/environments/dev"
test -f dev.backend.hcl || cp dev.backend.hcl.example dev.backend.hcl
test -f dev.tfvars || cp dev.tfvars.example dev.tfvars
```

Set backend `bucket` to the output and `allowed_cidr` to your public IP `/32` (default: public). Never commit local state or variable files.

## 3. Publish and deploy

From `terraform/environments/dev`:

```bash
terraform init -backend-config=dev.backend.hcl
terraform fmt -check -recursive "$LESSON_DIR/terraform"
terraform validate
terraform apply -target=module.ecr -var-file=dev.tfvars
REPO=$(terraform output -raw ecr_repository_url)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/arm64 -t "$REPO:v1" "$LESSON_DIR/app"
docker push "$REPO:v1"

terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
```

Updates require a new immutable image tag and matching `image_tag` in `dev.tfvars`.

## 4. Verify

Wait for ECS; print the public-IP discovery commands:

```bash
aws ecs wait services-stable --region "$AWS_REGION" \
  --cluster "$(terraform output -raw cluster_name)" \
  --services "$(terraform output -raw service_name)"
terraform output -raw get_public_ip
```

Run them, then set the returned IP below. Task replacements change it; `allowed_cidr` must allow your IP.

```bash
API_IP='<task-public-ip>'
curl --fail-with-body "http://$API_IP:8080/health"
curl --fail-with-body "http://$API_IP:8080/ready"
curl --fail-with-body -X POST "http://$API_IP:8080/todos" \
  -H 'Content-Type: application/json' -d '{"title":"hello from ECS"}'
curl --fail-with-body "http://$API_IP:8080/todos"
```

Expect `ok`, `ready`, and your saved todo.

## 5. Cleanup

From `terraform/environments/dev`:

```bash
terraform destroy -var-file=dev.tfvars
```

**Destroy deletes dev RDS without a final snapshot and removes ECR images.** The protected bootstrap bucket remains; retain its local state.
