# ECR repository

Private image registry with **immutable tags** (a tag always means the same image — push `v2` instead of overwriting `v1`), scan on push, and a lifecycle policy that keeps the last 10 images.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | 2–256 lowercase letters/digits separated by single `.` `_` `-` `/` |
| `force_delete` | `false` | Let destroy delete the repository while it still holds images (dev sets `true`) |

| Output | Use |
| --- | --- |
| `repository_url` | `docker tag` / `docker push` target and the ECS image prefix |

```hcl
module "ecr" {
  source       = "../../modules/ecr"
  name         = "lesson10-11-api"
  force_delete = true # dev only
}
```

Tests: [`tests/repository.tftest.hcl`](tests/repository.tftest.hcl).
