# Secrets

## Principles

- **Prefer no secret.** Workload identity (GKE Workload Identity, attached service accounts, GitHub OIDC to Workload Identity Federation) removes the key entirely.
- **One store.** Secret Manager (or Vault) is the source of truth; Kubernetes Secrets, CI secrets and env vars are delivery mechanisms that should be short-lived copies.
- **Least privilege per secret.** Grant `roles/secretmanager.secretAccessor` on the individual secret, not the project.
- **Rotate on a schedule and on exposure.** The [`secret-rotation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) skill covers dual-credential rotation without outage and finding leftover copies.

## Delivery patterns

| Platform | Pattern |
| --- | --- |
| GKE | Secret Manager add-on / CSI driver or External Secrets Operator with Workload Identity; application-layer secrets encryption with Cloud KMS |
| Cloud Run | Secret Manager references (`--set-secrets`), pinned to a version for reproducibility |
| GitHub Actions | OIDC for cloud access; environment secrets with required reviewers for anything else; never echo, never pass on the command line |
| Terraform | Data sources at apply time; remember values still land in state, so state is protected like a secret |

## Detection

- gitleaks in pre-commit and CI over the working tree and history (this repository runs it on every push).
- GitHub secret scanning with push protection.
- Watch logs for secrets: structured logging with redaction, and alerts on known token prefixes in log sinks.
- Audit `secretmanager.versions.access` with Data Access logs on production projects.

## When a secret leaks

Revoke or rotate first, then clean up: removing it from git history does not un-leak it. Find every copy (CI secrets, `.env` files, Kubernetes Secrets, laptops), check access logs for use during the exposure window, and record the timeline. The `compromise-evidence-preservation` skill covers preserving evidence before cleanup.
