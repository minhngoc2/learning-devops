# AGENTS.md

Learning repository of independent DevOps lessons. There is **no root build, test, lint, package manager, or CI**: each `lessonN/` is its own project, so `cd` into the lesson before running commands. Root README is Vietnamese; early lessons are Vietnamese notes, lessons 10–13 are English. Match the language of the file you edit.

## Layout

- `lesson1`, `lesson3`–`lesson8`: notes, small scripts, Dockerfiles, and diagram sources (`.excalidraw` / HTML / PNG). No test suite.
- `lesson10-11`, `lesson12`, `lesson13`: the substantial labs. Shared shape: `app/`, `terraform/environments/dev/`, `terraform/modules/*`, `quickstart.md`, per-module README.
- `docs/` and `.archify/` in these lessons are local, gitignored notes. In `lesson10-11` and `lesson13`, `*.md` is also ignored except `README.md`, `quickstart.md`, and module READMEs, so new markdown there will not appear in `git status`.
- The quickstarts are the source of truth for per-lesson setup, expected output counts, deploy, and cleanup. Read the relevant one before changing infrastructure.

## Terraform (lessons 10–11, 12, 13)

All roots require Terraform `>= 1.10, < 2.0` and AWS provider `~> 6.0`.

From a lesson directory:

```sh
terraform -chdir=terraform/environments/dev init
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
```

- `terraform test` uses a mocked AWS provider: no credentials, no real resources, no cost. Run it before `plan`.
- Run one test file with `terraform -chdir=<root> test -filter=tests/<name>.tftest.hcl`.
- `lesson10-11` and `lesson13` have a `bootstrap` root (S3 state bucket, local state); only `lesson10-11` has `environments/staging`. Create `dev.backend.hcl` from its example and init dev/staging with `-backend-config=dev.backend.hcl`. Lesson10-11's 27 test runs span all 3 roots and 5 modules; the dev root alone has only 3. To run all of them, loop over every folder with `terraform -chdir=terraform/<dir> init -backend=false` then `test` (the full loop is in `docs/04-terraform-and-state.md`, "Quality gates").
- TFLint `--config` must be absolute. Use `--config="$PWD/terraform/.tflint.hcl"`: with `--recursive`, a relative path silently falls back to default rules and skips AWS checks.
- checkov runs via `uvx checkov --config-file terraform/.checkov.yaml -d terraform`. Accepted lab findings and their reasons live in `.checkov.yaml`; read it before "fixing" a finding.
- State: `lesson10-11` and `lesson13` use their own bootstrap-created S3 backend (`lesson13` builds its bucket with the reusable `modules/state-bucket`; init dev with `-backend-config=dev.backend.hcl`, or `-backend=false` for offline checks). `lesson12` defaults to local state, with an opt-in S3 backend (`backend.tf.example` + `dev.backend.hcl.example`, both copies gitignored) that reuses the lesson10-11 bucket. Never commit `*.tfstate*`, plans, `*.tfvars`, or `*.backend.hcl`; copy the provided `*.example` files. Commit the `.terraform.lock.hcl` files for roots only. Module lock files created by tests are gitignored.
- Do not run `apply`, `destroy`, or any AWS-mutating command unless the user explicitly asks. Plans create billable resources; review before confirming.

## Apps

- Go labs (`lesson10-11`, `lesson13`): `go -C app test ./...`; single test with `go -C app test -run TestName ./...`.
- `lesson10-11`: the Fargate task is ARM64, so build images with `docker buildx build --platform linux/arm64`. Image tags are immutable; the pushed tag must match `image_tag` in `dev.tfvars`. `scripts/check-release.sh` checks a live deployment and calls AWS. Its offline test, `python3 scripts/test_check_release.py`, uses stubs and makes no AWS calls.
- `lesson12`: the active app is `nuxt-app/` (Nuxt 4, pnpm): `pnpm --dir nuxt-app install --frozen-lockfile`, then `pnpm --dir nuxt-app dev` or `generate`. `app/` is an archived React/Vite demo — do not follow its npm commands for deployment. Publishing uploads `nuxt-app/.output/public/`; `public/_nuxt/` is reserved for generated assets.
- `lesson13`: Lambda runs `build/bootstrap` on `provided.al2023`/arm64. Build with `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go -C app build -tags lambda.norpc -trimpath -o ../build/bootstrap .`; `build/` is gitignored. The binary name and `GOARCH` must match the module configuration.

## Verification order

`fmt` → `validate` → `test` (mocked) → optional TFLint/checkov → `plan`. Report the actual command output; do not claim a gate passed without running it.
