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
| GCP service-account key | Access tokens are bearer tokens that cannot be revoked; they stay valid until they expire (up to 60 minutes by default, up to 12 hours where an extended token lifetime is allowed) | Disable the key first (reversible). To block tokens already issued, disable the service account, which stops every workload using it, or apply an IAM deny policy on the account's principal (`principal://iam.googleapis.com/projects/-/serviceAccounts/SA_EMAIL`) to keep the account while you investigate. Re-enabling the account before the tokens expire makes them usable again, so wait out the longest token lifetime first. Delete the key after the bake period |
| AWS IAM user access key or role | Temporary credentials already issued (`GetSessionToken` sessions, assumed-role sessions) keep working until they expire unless a policy denies them | Deactivate the key and attach an explicit deny: on the user's unique ID (`aws:userid`), which also covers its `GetSessionToken` sessions; for a role, revoke active sessions, which attaches `AWSRevokeOlderSessions`, a deny on `aws:TokenIssueTime` older than now. Add a deny on any resource-based policy that grants the principal directly |
| GitHub token | A leaked PAT works until revoked or expired. App installation tokens expire after 1 hour. `GITHUB_TOKEN` expires when the job finishes or at its maximum lifetime: 6 hours on GitHub-hosted runners (the job limit), and 24 hours on self-hosted runners even though their jobs can run for 5 days | Revoke the PAT or the OAuth/App authorisation; revoke a leaked installation token with `DELETE /installation/token` (authenticated with that token); rotate any secret the token could read |
| Kubernetes service-account token | Legacy Secret-based tokens never expire. Since Kubernetes 1.29 (LegacyServiceAccountTokenCleanUp: alpha 1.28, beta and on by default 1.29, GA 1.30) auto-generated legacy tokens unused for a year (the default `--legacy-service-account-token-clean-up-period`) are marked invalid and deleted after another unused year; manually created token Secrets are not cleaned up. Bound (projected or TokenRequest) tokens live until their expiry and there is no per-token revocation | Delete the token Secret for a legacy token; for bound tokens, delete and recreate the service account, which changes its UID and invalidates every token issued for it, or delete the pod a token is bound to once that pod's evidence is captured |

Sources: [Google Cloud: handle compromised credentials](https://cloud.google.com/docs/security/compromised-credentials), [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token), [GitHub: installation access tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app), [Kubernetes: legacy token cleanup](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#auto-generated-legacy-serviceaccount-token-clean-up).

Full inventory queries, telemetry tables, incident path and anti-patterns are in the original skill.
