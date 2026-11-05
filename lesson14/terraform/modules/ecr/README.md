# ECR repositories

One private image registry per name, each with **immutable tags** (a tag always means the same image — push `v2` instead of overwriting `v1`), scan on push, and a lifecycle policy that keeps the last 10 images.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `names` | Required | Set of repository names; each 2–256 lowercase letters/digits separated by single `.` `_` `-` `/` |
| `force_delete` | `false` | Let destroy delete repositories while they still hold images (dev sets `true`) |

| Output | Use |
| --- | --- |
| `repository_urls` | Map name → URL: `docker tag` / `docker push` target and the ECS image prefix |

```hcl
module "ecr" {
  source       = "../../modules/ecr"
  names        = [for s in ["user", "product", "cart", "order", "payment", "notification"] : "lesson14/${s}"]
  force_delete = true # dev only
}
```

Tests: [`tests/repository.tftest.hcl`](tests/repository.tftest.hcl).
