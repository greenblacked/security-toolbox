# Security Toolbox

Practical security checks, best practices and automated guardrails for cloud platforms, Kubernetes, CI/CD and infrastructure.

Report / dry-run first. Complements [ops-toolbox](https://ops.szolotov.com).

## Areas

- **Kubernetes / GKE** — CIS benchmarks, Pod Security Standards, RBAC, NetworkPolicy
- **GCP** — Cloud Custodian policies, IAM, logging and organisation baselines
- **Terraform / IaC** — Checkov, OPA/Conftest, secure module patterns
- **GitHub & CI** — Org and repository hardening, Actions permissions, supply-chain pinning
- **Secrets** — Handling patterns and validation

Site published at [security.szolotov.com](https://security.szolotov.com).

## What is in the repository

- **Policies** (`policies/`): OPA/Conftest rules for GCP Terraform plans (service-account keys, public buckets, admin ports open to the internet) and Kubernetes pod security, plus Checkov custom checks, each with good/bad fixtures.
- **Checks** (`checks/`): read-only GKE hardening report, Kubernetes CIS 5.1/5.2 workload report, and a GitHub Actions hardening note.
- **Skills** (`plugins/security/skills/`): written procedures for IaC review, image hardening, secret rotation, access review, host hardening, security review, threat modelling, dependency triage, certificate automation, detection engineering and compromise evidence preservation.
