# Lesson 10–11: Go API on ECS Fargate

A small Go todo API backed by RDS PostgreSQL, deployed to AWS with Terraform. This lesson includes the bootstrap and dev environments.

## Dev architecture

![Dev architecture: Terraform state, ECR, public Fargate API, private RDS, Secrets Manager and CloudWatch Logs](dev-architecture.png)

- Bootstrap creates a private, encrypted, versioned S3 bucket for dev Terraform state, with S3 lockfile locking.
- Dev creates a `10.0.0.0/16` VPC with public and private subnets across two availability zones. One ARM64 Fargate task serves HTTP on port 8080 through its public IP and the internet gateway.
- ECR stores the API image. ECS reads the RDS-managed password from Secrets Manager at task startup and sends container logs to CloudWatch.
- PostgreSQL 17 runs as an encrypted, Single-AZ RDS instance in private subnets. Its security group accepts port 5432 only from the API security group; the API requires TLS for the database connection.

## Repository structure

```text
lesson10-11/
├── README.md
├── dev-architecture.png
├── app/                        # Go API, tests, Dockerfile and local Compose stack
└── terraform/
    ├── bootstrap/              # S3 state bucket; bootstrap state stays local
    ├── environments/dev/       # Dev resources, remote backend and example config
    └── modules/
        ├── network/            # VPC, subnets, internet gateway and routes
        ├── ecr/                # Container registry
        ├── ecs/                # Fargate service, IAM, security group and logs
        └── rds/                # PostgreSQL, private subnet group and security group
```

## Run and deploy

Run locally with `cd app && docker compose up --build`. The API exposes `GET /health`, `GET /ready`, `GET /todos` and `POST /todos` with a JSON `title`.

For AWS, apply `terraform/bootstrap` first. In `terraform/environments/dev`, copy `dev.backend.hcl.example` and `dev.tfvars.example` to their corresponding filenames without `.example`, fill in the state bucket, then initialize with `terraform init -backend-config=dev.backend.hcl`. Create the registry with `terraform apply -target=module.ecr -var-file=dev.tfvars`, build and push the app image for `linux/arm64` to that registry, then plan and apply dev with `-var-file=dev.tfvars`. Use a fresh image tag for each release.

Dev is a lab: the task public IP can change, HTTP has no authentication, and the default ingress permits all IPv4 addresses. Narrow `allowed_cidr` when needed. Destroying dev deletes the database without a final snapshot and removes ECR images; AWS resources incur charges while they exist.
