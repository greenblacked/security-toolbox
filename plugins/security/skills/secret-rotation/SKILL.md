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

Full inventory queries, telemetry tables, incident path and anti-patterns are in the original skill.
