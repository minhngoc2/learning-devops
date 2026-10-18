# Quickstart

Run from `lesson10-11/`. Local development requires Docker Compose. AWS deployment also requires Terraform >= 1.10 and < 2.0, AWS CLI credentials, and permissions to create the lab resources.

## Run locally

```bash
cd app
docker compose up -d --build
curl --fail-with-body http://localhost:8080/ready
curl --fail-with-body -X POST http://localhost:8080/todos \
  -H 'Content-Type: application/json' -d '{"title":"hello locally"}'
curl --fail-with-body http://localhost:8080/todos
```

If the API is still starting, retry `/ready`. Stop with `docker compose down`.

## Deploy dev to AWS

For a new deployment, start in `lesson10-11/`. For an existing deployment, reuse its backend configuration and bootstrap state.

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
cp -n dev.backend.hcl.example dev.backend.hcl
cp -n dev.tfvars.example dev.tfvars
```

Set `bucket` in `dev.backend.hcl` to the bootstrap output. Set `allowed_cidr` in `dev.tfvars` to your public IP with `/32` to restrict API access, or retain the public lab default. Then create ECR and publish the image before deploying the service:

```bash
terraform init -backend-config=dev.backend.hcl
terraform apply -target=module.ecr -var-file=dev.tfvars
REPO=$(terraform output -raw ecr_repository_url)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/arm64 -t "$REPO:v1" "$LESSON_DIR/app"
docker push "$REPO:v1"

terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
```

For subsequent releases, use a new image tag and set the same `image_tag` in `dev.tfvars` before planning and applying.

## Verify

Wait for the service to stabilize, then print the commands that discover the task public IP:

```bash
aws ecs wait services-stable --region "$AWS_REGION" \
  --cluster lesson10-11-dev --services lesson10-11-dev
terraform output -raw get_public_ip
```

Run the printed commands, then use the returned IP:

```bash
API_IP='<task-public-ip>'
curl --fail-with-body "http://$API_IP:8080/health"
curl --fail-with-body "http://$API_IP:8080/ready"
curl --fail-with-body -X POST "http://$API_IP:8080/todos" \
  -H 'Content-Type: application/json' -d '{"title":"hello from ECS"}'
curl --fail-with-body "http://$API_IP:8080/todos"
```

## Clean up

AWS resources incur charges. When the lab data is no longer needed, run this from `terraform/environments/dev`:

```bash
terraform destroy -var-file=dev.tfvars
```

This deletes the database without a final snapshot and removes ECR images. The bootstrap state bucket remains; preserve the local bootstrap state file.
