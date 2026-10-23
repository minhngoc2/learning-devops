# Lesson 10–11: Go API + PostgreSQL on ECS Fargate

A Go todo API on ECS Fargate with a private RDS PostgreSQL database, deployed by Terraform with remote S3 state.

![Go 1.27](https://img.shields.io/badge/Go-1.27-00ADD8?logo=go&logoColor=white)
![Terraform 1.10+](https://img.shields.io/badge/Terraform-%E2%89%A5%201.10-7B42BC?logo=terraform&logoColor=white)
![terraform test 27/27](https://img.shields.io/badge/terraform%20test-27%2F27-brightgreen)
![checkov 98/98](https://img.shields.io/badge/checkov-98%2F98-brightgreen)

> [!NOTE]
> One ARM64 Fargate task serves the API on port 8080; RDS stays private. A `bootstrap` root creates the S3 state bucket used by the `dev` and `staging` roots.

- **[Quickstart](quickstart.md)**: run locally, bootstrap state, publish the image, deploy, verify, cleanup
- Modules: [network](terraform/modules/network/README.md) · [ecr](terraform/modules/ecr/README.md) · [rds](terraform/modules/rds/README.md) · [alb](terraform/modules/alb/README.md) · [ecs](terraform/modules/ecs/README.md)

## Architecture

**Client → Internet gateway → Fargate task (`:8080`) → RDS PostgreSQL (`:5432`, private)**

![Dev architecture: client to the internet gateway and a public Fargate task on 8080, task to private RDS on 5432, across two pinned AZs; image pulls, secret reads and logs leave through the internet gateway](dev-architecture.png)

- **API:** One public ARM64 Fargate task, across two pinned AZs.
- **Database:** Private, encrypted RDS PostgreSQL 17. Port 5432 accepts traffic only from the API security group.
- **Images and secrets:** ECR stores the image; Secrets Manager supplies the database password at startup. Both go through the internet gateway (no NAT or VPC endpoints).
- **Logs and state:** CloudWatch collects logs; S3 stores Terraform state with locking.

Diagram source: [`diagrams/dev-architecture.json`](diagrams/dev-architecture.json) (Archify).

## API

| Request | Status | Meaning |
| --- | --- | --- |
| `GET /health` | `200` `ok` | The process is up |
| `GET /ready` | `200` `ready` | The database is reachable |
| `POST /todos` with `{"title":"..."}` | `201` | Saves a todo; a blank title or invalid JSON returns `400` |
| `GET /todos` | `200` | Lists saved todos |

## Results

| Check | Result |
| --- | --- |
| `terraform test` (mocked AWS) | 27 passed: bootstrap 2, dev 3, staging 2, alb 3, ecs 6, rds 5, network 4, ecr 2 |
| TFLint (Terraform + AWS rulesets) | No issues |
| Checkov | 98 passed, 0 failed |
| ECS service `lesson10-11-dev` | Deployed; one healthy task (`lesson10-11-dev:3`) |
| `/health`, `/ready` | `ok`, `ready` (database connected) |
| `GET /todos` | Four saved todos returned |

The live rows were recorded on October 15, 2026, before the October 22 Terraform review; the stack has since been destroyed. The static checks were re-run after the review.

> [!TIP]
> Commands, sample output and screenshots are in the [quickstart](quickstart.md).

## Lessons learned

> [!IMPORTANT]
> Image tags are immutable. Every release needs a new tag, and `image_tag` in `dev.tfvars` must match the pushed tag.

- **Build for the task's CPU.** The task is ARM64, so images need `docker buildx build --platform linux/arm64`.
- **`/health` and `/ready` answer different questions.** One says the process is alive, the other that the database is reachable.
- **TFLint's `--config` must be an absolute path.** With `--recursive`, a relative path silently falls back to default rules and skips AWS checks.

> [!CAUTION]
> AWS resources incur charges until removed. `destroy` deletes dev RDS **without a final snapshot** and removes ECR images. Follow the [cleanup steps](quickstart.md#5-cleanup).
