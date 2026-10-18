# Lesson 10–11: Go API + PostgreSQL on AWS

**Assignment:** Build an API connected to a database, deploy the API to ECS and the database to RDS, and submit the ECS public endpoint and an architecture diagram.

## Result

Deployed and verified on **18 October 2026**:

- API: [GET /todos](http://13.213.73.233:8080/todos). Created and retrieved four todos successfully.
- Health: `/health` returned `ok`; `/ready` returned `ready`, confirming database connectivity.
- ECS: `lesson10-11-dev` deployed successfully with one healthy Fargate task (`lesson10-11-dev:3`).
- Evidence: [API response](evidence/dev-api-todos.png) · [ECS service](evidence/dev-ecs-service.png).

## Architecture

![Dev architecture](dev-architecture.png)

Terraform provisions a public ARM64 Fargate task serving the Go API on port 8080 and a private, encrypted RDS PostgreSQL 17 instance. Only the API security group can reach the database on port 5432. ECR stores the image, Secrets Manager supplies the database password at startup, CloudWatch collects logs, and S3 stores dev Terraform state with locking.

This dev lab uses HTTP without authentication; the public IP may change when the task is replaced.

See [quickstart.md](quickstart.md) for local development and AWS deployment.
