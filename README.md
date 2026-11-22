# Security Toolbox

[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Security checks, best practices, automated guardrails and policy-as-code for cloud platforms (GCP primary), Kubernetes, Terraform, GitHub Actions / CI, secrets and supply chain.

Practical, report / dry-run first. Complements [ops-toolbox](https://github.com/greenblacked/ops-toolbox). Documentation site: [security.szolotov.com](https://security.szolotov.com).

## Quick start

```bash
git clone https://github.com/greenblacked/security-toolbox.git
cd security-toolbox
# Read-only reports
./checks/gke/gke-report.sh --cluster prod --location europe-west1
./checks/kubernetes/cis-workload-report.sh
# Policy against a Terraform plan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
# Self-tests against fixtures
./checks/test.sh && ./policies/test.sh
# Rebuild the documentation site into site/, then check it
npm ci --ignore-scripts && node scripts/build_site.cjs
python scripts/check_site.py site
```

## What's here

| Area | Purpose | Start here |
| --- | --- | --- |
| Kubernetes / GKE | GKE hardening report, CIS 5.1 / 5.2 workload report, pod security policy | `checks/gke/`, `checks/kubernetes/`, `policies/opa/kubernetes/` |
| GCP | IAM, storage, network and logging baseline | `docs/gcp/`, `policies/opa/terraform/` |
| Terraform / IaC | OPA/Conftest on plan JSON, Checkov custom checks | `policies/opa/terraform/`, `policies/checkov/` |
| GitHub / CI | Actions hardening, repo and org baseline | `checks/github/actions-hardening.md`, `docs/github/` |
| Secrets | Handling, delivery and rotation patterns | `docs/secrets/`, `secret-rotation` skill |
| Skills | Written procedures for IaC review, image hardening, secret rotation, access review, host hardening, security review, threat modelling, dependency triage, certificate automation, detection engineering, compromise evidence preservation. Each one is published in full, with its reference files, at `/skills/` | `plugins/security/skills/` |

## Principles

- Report or dry-run first. Explicit apply flag for any change.
- Modular. One check or policy usable alone.
- Tested and documented.
- No secrets in the repository.

## Structure

```text
checks/     # read-only report scripts and checklists, with fixtures
policies/   # OPA/Conftest and Checkov policies, with fixtures
plugins/    # security skills (SKILL.md procedures, published at /skills/)
docs/       # Markdown guide source
scripts/    # site build, deployment helpers and their tests
site/       # hand-written homepage, styles and headers; generated routes are gitignored
```

`scripts/build_site.cjs` renders `docs/`, `checks/`, `policies/` and `plugins/` into `site/`. The Markdown stays the source of truth, and the generated routes are ignored by Git so a local build leaves a clean tree.

See [docs/](docs/) and the live site when published.
