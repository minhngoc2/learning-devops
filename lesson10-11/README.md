# Lesson 10–11: Go API + PostgreSQL on AWS

**Goal:** Deploy a Go todo API to ECS Fargate and PostgreSQL to private RDS using Terraform.

Start with the [quickstart](quickstart.md) for local development, deployment, verification, and cleanup.

## Architecture

![Dev architecture](dev-architecture.png)

- **API:** One public ARM64 Fargate task serving the Go API on port 8080.
- **Database:** Private, encrypted RDS PostgreSQL 17; port 5432 accepts traffic only from the API security group.
- **Images and secrets:** ECR stores the image; Secrets Manager supplies the database password at startup.
- **Logs and state:** CloudWatch collects logs; S3 stores dev Terraform state with locking.

## Result

- **API:** [GET /todos](http://13.213.73.233:8080/todos) returned four successfully created todos.
- **Health:** `/health` returned `ok`; `/ready` returned `ready`, confirming database connectivity.
- **ECS:** `lesson10-11-dev` deployed successfully with one healthy Fargate task (`lesson10-11-dev:3`).

## Evidence

Terraform test excerpts (mocked AWS; no real resources created):

```text
$ terraform -chdir=terraform/modules/ecs test
  run "dev_direct_access"... pass
  run "staging_alb_access"... pass
  run "reject_missing_ingress_source"... pass

Success! 3 passed, 0 failed.

$ terraform -chdir=terraform/modules/rds test
  run "protected_defaults"... pass
  run "unique_final_snapshot"... pass
  run "dev_skips_final_snapshot"... pass

Success! 3 passed, 0 failed.
```

![API response showing four saved todos](evidence/dev-api-todos.png)

![ECS service showing a successful deployment and one healthy task](evidence/dev-ecs-service.png)
