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

## Rotating without an outage

A rotation is finished when every consumer is provably on the new credential and the old one is deleted. The order matters more than the tooling:

1. Inventory consumers from access logs and provider telemetry, not from the runbook, so a job nobody remembered still shows up.
2. Issue a **second** credential alongside the first. Never edit a credential in place: there is no overlap to roll back to.
3. Move consumers, then prove adoption from the provider's last-used data past its reporting lag. A metric that has not caught up is not evidence.
4. Disable the old credential, bake for a period longer than the longest token lifetime it could have issued, then delete it.
5. Keep the alert you used to prove adoption: it catches the consumer you missed next time.

In an incident, revoke first and investigate second. Removing the secret from git history revokes nothing.

## Never

- Print a secret, pass it on a command line (visible in `ps` and shell history), or echo it into a log.
- Store the same secret in more than one place without recording that the copy exists.
- Treat `sensitive = true` in Terraform, or a Kubernetes Secret, as encryption: both are readable by anyone with state or namespace access.
- Rely on `noindex`, a private repository, or a deleted commit as access control.

## When a secret leaks

Revoke or rotate first, then clean up: removing it from git history does not un-leak it. Disabling a key does not end the short-lived tokens already issued from it (a GCP access token minted from a service-account key stays valid until it expires, an hour by default), so also revoke sessions where the platform allows it; the [`secret-rotation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) skill lists how per platform. Find every copy (CI secrets, `.env` files, Kubernetes Secrets, laptops), check access logs for use during the exposure window, and record the timeline. The `compromise-evidence-preservation` skill covers preserving evidence before cleanup.
