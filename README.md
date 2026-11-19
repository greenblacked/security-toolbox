# Security Toolbox

[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Security checks, best practices, automated guardrails and policy-as-code for cloud platforms (GCP primary), Kubernetes, Terraform, GitHub Actions / CI, secrets and supply chain.

Practical, report / dry-run first. Complements [ops-toolbox](https://github.com/greenblacked/ops-toolbox). Documentation site: [security.szolotov.com](https://security.szolotov.com) (coming soon).

## Quick start

```bash
git clone https://github.com/greenblacked/security-toolbox.git
cd security-toolbox
# First reports (read-only)
# ./checks/kubernetes/status.sh   # coming
# ./checks/gcp/status.sh          # coming
```

## What's here

| Area | Purpose | First command |
| --- | --- | --- |
| Kubernetes / GKE | CIS, Pod Security, RBAC, NetworkPolicy reports | coming |
| GCP | Cloud Custodian policies, IAM, logging baselines | coming |
| Terraform / IaC | Checkov / OPA / secure module patterns | coming |
| GitHub / CI | Org/repo hardening, Actions permissions, pinning | coming |
| Secrets | Handling patterns and checks | coming |

## Principles

- Report or dry-run first. Explicit apply flag for any change.
- Modular. One check or policy usable alone.
- Tested and documented.
- No secrets in the repository.

## Structure

```
checks/     # executable report scripts
policies/   # Custodian, OPA, Kyverno, etc.
docs/       # MkDocs source for security.szolotov.com
examples/
```

See [docs/](docs/) and the live site when published.
