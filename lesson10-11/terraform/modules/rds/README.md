# RDS PostgreSQL

Private, encrypted PostgreSQL instance (gp3, 20 GB), its DB subnet group, and a security group **without ingress** — the caller adds the rule from its API security group. RDS generates the master password and stores it in Secrets Manager (`manage_master_user_password`), so it never appears in Terraform state. Minor versions auto-upgrade and tags are copied to snapshots.

| Input | Default | Purpose / rule |
| --- | --- | --- |
| `name` | Required | RDS identifier: 1–63 lowercase letters/digits/single hyphens, starts with a letter |
| `vpc_id` | Required | VPC for the DB SG |
| `subnet_ids` | Required | At least two distinct private subnets |
| `engine_version` | `"17"` | PostgreSQL major version only (validated); AWS applies minor upgrades automatically |
| `instance_class` | `"db.t4g.micro"` | Instance size |
| `db_name`, `username` | `"app"` | Start with a letter; letters/digits/underscores; ≤ 63 |
| `multi_az` | `false` | Standby in a second AZ |
| `backup_retention_period` | `1` | 0–35 days |
| `deletion_protection` | `true` | Keep on for anything that is not a lab |
| `skip_final_snapshot` | `false` | Skip the snapshot on destroy |
| `final_snapshot_identifier` | `null` | Defaults to `<name>-final`; starts with a letter, letters/digits/single hyphens, ≤ 255 |

| Output | Use |
| --- | --- |
| `address`, `port`, `db_name`, `username` | App environment variables |
| `secret_arn` | ECS secret `"${secret_arn}:password::"` |
| `security_group_id` | Target of the caller's ingress rule |

Dev overrides the safe defaults to make the lab disposable (`deletion_protection = false`, `skip_final_snapshot = true`, `backup_retention_period = 0`); staging keeps them. Tests: [`tests/snapshots.tftest.hcl`](tests/snapshots.tftest.hcl).
