# Secrets

**Who this is for:** engineers who own a credential and the systems that consume it, and the reviewers who approve changes to either.

## Principles

- **Prefer no secret.** Workload identity (GKE Workload Identity, attached service accounts, GitHub OIDC to Workload Identity Federation) removes the key entirely.
- **One store.** Secret Manager (or Vault) is the source of truth; Kubernetes Secrets, CI secrets and env vars are delivery mechanisms that should be short-lived copies.
- **Least privilege per secret.** Grant `roles/secretmanager.secretAccessor` on the individual secret, not the project.
- **Rotate on a schedule and on exposure.** The [`secret-rotation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) skill covers dual-credential rotation without outage and finding leftover copies.

## What counts as a secret

Not everything sensitive is a secret, and the difference decides how it is stored, rotated and logged.

| Kind | Example | Lifetime | If it leaks |
| --- | --- | --- | --- |
| Long-lived credential | Service-account key, PAT, API key, database password | Months to never | Full access as that identity until someone notices |
| Short-lived token | OIDC token, access token, signed URL, session cookie | Minutes to hours | Access until expiry; revocable only by revoking the session |
| Encryption key | KMS key, DEK | Years | Every ciphertext it protected, plus future ones |
| Configuration with a secret inside | Connection string, `.env`, Terraform state | As long as the file | Whatever the embedded credential grants |
| Personal data | Customer record, email, address | As long as the retention policy | A privacy obligation, not just an access problem |

The first two are the ones people mean by "secret". The fourth is the one that leaks most often, because nobody classified it.

## Storage and envelope encryption

- **A managed secret store, not a file.** Secret Manager (or Vault) gives versioning, access audit, IAM per secret and rotation hooks. An encrypted file in a repository gives none of those.
- **Envelope encryption where the store is not enough.** A data key encrypts the payload; a KMS key encrypts the data key. The ciphertext can live anywhere, and access is decided by `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key — which is revocable in one place.
- **CMEK on the secret store itself** for regulated data, so revoking the key makes the ciphertext unreadable.
- **Cloud KMS Autokey** creates key rings and keys on demand, with a fixed rotation period and separation of duties: a developer can request a key for a resource without holding the permissions to use or manage keys. It removes the usual reason CMEK adoption stalls.
- **Version, do not overwrite.** Secret Manager keeps versions; consumers pin a version or read `latest` deliberately. An overwritten value has no rollback and no record of what it was.
- **Name secrets for the consumer**, not the technology: `payments-api/stripe-key`, so an access review can answer "who can read the payments secret" without reading code.

## Delivery patterns

| Platform | Pattern |
| --- | --- |
| GKE | Secret Manager add-on / CSI driver or External Secrets Operator with Workload Identity; application-layer secrets encryption with Cloud KMS |
| Cloud Run | Secret Manager references (`--set-secrets`), pinned to a version for reproducibility |
| GitHub Actions | OIDC for cloud access; environment secrets with required reviewers for anything else; never echo, never pass on the command line |
| Terraform | Data sources at apply time; remember values still land in state, so state is protected like a secret |
| Compute Engine | Instance metadata is not a secret store; use the metadata server only for identity, and fetch secrets with it |
| Local development | A short-lived token from the same identity provider, never a copy of production; a `.env` file in `.gitignore` is a last resort with an expiry |

Delivery is where most leaks happen, because the value has to exist somewhere the process can read it.

- **Environment variables are visible** in `/proc/<pid>/environ`, in crash dumps and in some framework debug pages. A file mount is better; a client that fetches at use is better still.
- **A mounted secret is a copy.** Rotating the source does not update a file that was mounted at start. Either restart the workload or use a client that re-reads.
- **Init containers that write a secret to a shared volume** leave it on disk for the life of the pod. Prefer a projected volume mounted read-only into the container that needs it.
- **Immutable revisions keep old values.** A Cloud Run revision that embedded a secret still has it after the secret is rotated; replacing the revision is part of the rotation.

## Dynamic credentials

The strongest answer to "where is the secret" is that there isn't one.

- **Cloud SQL IAM database authentication**: the application authenticates with its workload identity and a short-lived token instead of a password.
- **Vault dynamic secrets**: a database or cloud credential is issued on demand with a TTL, and revocation is immediate and central.
- **Workload identity everywhere else**: GKE, Cloud Run, Cloud Functions, CI. The credential is minted for the workload, expires, and cannot be copied off the host in a usable form.
- **STS and token exchange** for cross-cloud access, so one cloud's identity is exchanged for another's short-lived credential rather than a shared key.

Each of these removes a rotation problem and a copy of the secret from disk. Where they are available, a static secret is a choice, not a constraint.

## Detection

- gitleaks in pre-commit and CI over the working tree and history (this repository runs it on every push).
- GitHub secret scanning with push protection.
- Watch logs for secrets: structured logging with redaction, and alerts on known token prefixes in log sinks.
- Audit `secretmanager.versions.access` with Data Access logs on production projects.

Detection is worth more than prevention here, because the leak usually happens through a path nobody reviewed: a debug log, a stack trace, a screenshot in a ticket.

- **Scan the history, not just the diff.** A secret committed a year ago and deleted in the next commit is still in the clone.
- **Scan the artifacts too**: CI logs, build outputs, container layers, Terraform state, and the `.env` files that get zipped into a support bundle.
- **Alert on the access pattern, not only the value**: a secret read from a new principal, a spike in `versions.access`, or a read from outside the expected network.
- **A push-protection block is a signal.** Someone tried to commit a credential; that credential is probably still valid somewhere.

```bash
# Who read this secret, and from where
gcloud logging read 'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --limit=20 --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)'
# Secrets with no rotation configured
gcloud secrets list --format='table(name,rotation.nextRotationTime)' --filter='NOT rotation.nextRotationTime:*'
```

## Rotating without an outage

A rotation is finished when every consumer is provably on the new credential and the old one is deleted. The order matters more than the tooling:

1. Inventory consumers from access logs and provider telemetry, not from the runbook, so a job nobody remembered still shows up.
2. Issue a **second** credential alongside the first. Never edit a credential in place: there is no overlap to roll back to.
3. Move consumers, then prove adoption from the provider's last-used data past its reporting lag. A metric that has not caught up is not evidence.
4. Disable the old credential, bake for a period longer than the longest token lifetime it could have issued, then delete it.
5. Keep the alert you used to prove adoption: it catches the consumer you missed next time.

In an incident, revoke first and investigate second. Removing the secret from git history revokes nothing.

Three platform features make the last two steps safer than they used to be. Secret Manager supports a **delayed destruction** window per secret, so a destroyed version is disabled at once but stays recoverable while the window is open. **Custom organisation constraints** for Secret Manager can require a rotation schedule and an expiry on every secret, which turns a wiki rule into an admission-time block. The **GKE Secret Manager add-on** can push a new version into running pods, which removes the restart that used to be part of the rotation.

## Never

- Print a secret, pass it on a command line (visible in `ps` and shell history), or echo it into a log.
- Store the same secret in more than one place without recording that the copy exists.
- Treat `sensitive = true` in Terraform, or a Kubernetes Secret, as encryption: both are readable by anyone with state or namespace access.
- Rely on `noindex`, a private repository, or a deleted commit as access control.

## When a secret leaks

Revoke or rotate first, then clean up: removing it from git history does not un-leak it. Disabling a key does not end the short-lived tokens already issued from it (a GCP access token minted from a service-account key stays valid until it expires, an hour by default), so also revoke sessions where the platform allows it; the [`secret-rotation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) skill lists how per platform. Find every copy (CI secrets, `.env` files, Kubernetes Secrets, laptops), check access logs for use during the exposure window, and record the timeline. The [`compromise-evidence-preservation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/compromise-evidence-preservation/SKILL.md) skill covers preserving evidence before cleanup.

The sequence, in order:

1. **Revoke.** Disable the credential, then invalidate the sessions and tokens it minted.
2. **Scope.** Which logs show use during the exposure window, from which addresses and which principals? That answer sets whether this is a leak or a compromise.
3. **Preserve.** Capture the logs and the access records before rotating further, because rotation destroys the correlation you need.
4. **Rotate everything downstream.** A leaked CI token can read every secret the job could read. Those are leaked too.
5. **Record** the timeline, the consumers found, and the control that failed — not just the credential.

## Next

- [Secret Rotation](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) — the full procedure, per platform.
- [GCP](https://github.com/greenblacked/security-toolbox/blob/main/docs/gcp/index.md) — organisation policies that prevent the key from existing.
- [GitHub Actions](https://github.com/greenblacked/security-toolbox/blob/main/docs/github/index.md) — OIDC instead of secrets in CI.
