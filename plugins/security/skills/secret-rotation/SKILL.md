---
name: secret-rotation
description: "Rotate a credential, or contain one that has leaked, without an outage or a leftover copy: choose the planned or incident path first, inventory every consumer from access logs not the runbook, issue a second live credential not an in-place edit, prove adoption from last-used telemetry past reporting lag, then disable, bake and delete. Use when rotating, replacing, expiring or revoking an API key, access key, token, service-account key, database password, signing secret or certificate; when a secret has been committed, pushed or pasted somewhere it should not be; when someone with access leaves or a vendor reports a breach; or for \"this key is in a public repo\" or \"how do we roll this password without downtime\". Not for designing authentication, choosing a secrets manager, reviewing IAM policy, history scrubbing, certificate renewal, or federation such as IRSA or GitHub OIDC."
allowed-tools: "Read, Grep, Glob"
---

# Secret Rotation

A rotation is finished when every consumer is provably on the new credential, the old one is deleted, and nothing paged. A leak is contained when the credential stops working — not when the commit is gone.

Adapted from greenblacked/AI plugins/security/skills/secret-rotation.

## Hard gates

1. Decide planned or incident before touching anything.
2. Issue a second credential; do not edit one in place.
3. Disable the old credential first, delete it later.
4. Adoption is proven by provider-side last-used telemetry, past reporting lag.
5. In an incident, revoke before you investigate.
6. Rewriting git history revokes nothing.
7. The new secret never travels through a channel that retains it.

## Revocation is not instant

Disabling or deleting a long-lived credential stops new authentications with it. It does not end the short-lived credentials already minted from it, so in an incident revoke those too:

| Platform | What survives disabling the key | How to end it |
| --- | --- | --- |
| GCP service-account key | Access tokens issued from the key stay valid until they expire (1 hour by default) | Disable the key first (reversible), then disable the service account itself, which revokes its short-lived credentials; that also stops every workload using the account, so plan for it. Delete the key after the bake period |
| AWS IAM user access key or role | Temporary credentials already issued (`GetSessionToken` sessions, assumed-role sessions) keep working until they expire unless a policy denies them | Deactivate the key and attach an explicit deny: on the user's unique ID (`aws:userid`), which also covers its `GetSessionToken` sessions; for a role, revoke active sessions, which attaches `AWSRevokeOlderSessions`, a deny on `aws:TokenIssueTime` older than now. Add a deny on any resource-based policy that grants the principal directly |
| GitHub token | A leaked PAT works until revoked or expired; `GITHUB_TOKEN` and app installation tokens expire on their own (the job's end or at most 24 hours) | Revoke the PAT or the OAuth/App authorisation; rotate any secret the token could read |
| Kubernetes service-account token | Legacy Secret-based tokens never expire; bound (projected or TokenRequest) tokens live until their expiry and there is no per-token revocation | Delete the token Secret for a legacy token; for bound tokens, delete and recreate the service account, which changes its UID and invalidates every token issued for it, or delete the pod a token is bound to once that pod's evidence is captured |

Full inventory queries, telemetry tables, incident path and anti-patterns are in the original skill.
