# GitHub & CI

**Who this is for:** maintainers who own workflows that can deploy, publish or reach a cloud credential. You should be comfortable editing YAML workflows.

The full workflow guidance is in [`checks/github/actions-hardening.md`](https://github.com/greenblacked/security-toolbox/blob/main/checks/github/actions-hardening.md): SHA pinning, minimal `GITHUB_TOKEN` permissions, `pull_request_target` risks, `persist-credentials: false`, env indirection for `${{ }}` in `run:`, and OIDC instead of long-lived cloud secrets.

## Workflow hardening patterns

A workflow that can be edited by a contributor can reach a deployment credential. Set the token's reach first, then the permissions of each job:

```yaml
name: deploy
on:
  push:
    branches: [main]
permissions: {}                    # nothing at the top level
jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      id-token: write              # an OIDC token, not a stored cloud key
    steps:
      - uses: actions/checkout@<commit-sha>  # v4.2.2
        with:
          persist-credentials: false
      - uses: google-github-actions/auth@<commit-sha>  # v2.1.8
        with:
          workload_identity_provider: ${{ vars.WIF_PROVIDER }}
          service_account: ${{ vars.DEPLOY_SA }}
```

- **Pin to a commit SHA, record the tag in a comment.** A tag can be moved; the comment is what makes the pin reviewable. Dependabot can keep both current.
- **Never put `${{ }}` inside `run:`.** The expression is substituted into the script before bash parses it, so a pull request title or branch name can become shell syntax. Pass the value through `env:` and quote it.
- **`pull_request_target` runs with the base repository's token and secrets.** If you use it, do not check out the pull request head, and never execute code from it.
- **`persist-credentials: false`** keeps the checkout token out of `.git/config`, where a later step in the same job could read it.
- **Prefer OIDC over stored cloud secrets** for AWS, GCP and Azure: the trust policy pins the repository, branch or environment, so a fork or a different workflow cannot assume the role.
- **Environment secrets with required reviewers** are the control for anything that must remain a static secret.

## The token and permission model

Every job gets a `GITHUB_TOKEN` minted for that run. Its scope is the whole security question, and the defaults are not safe by accident.

- `permissions: {}` at the top of the file, then the minimum per job. A top-level `write-all` is a repository takeover path when combined with any step that runs untrusted code.
- `contents: write` on a job that checks out a pull request is the combination to look for. So is `pull-requests: write` on anything triggered by `issue_comment`.
- `id-token: write` is not a data permission: it mints an OIDC token and nothing else. Grant it only to the job that exchanges it.
- `actions: write` lets a workflow dispatch or cancel others, including its own successors.
- Set the repository default to read-only (**Settings → Actions → General → Workflow permissions**) so a workflow that forgets a `permissions` block fails closed rather than open.
- Require approval for first-time contributors, and disable "Allow GitHub Actions to create and approve pull requests".

`GITHUB_TOKEN` is short-lived and scoped to the repository, which is why it is better than a PAT. A fine-grained PAT is a long-lived credential with a person's access; use it only where no App or OIDC path exists, with an expiry and an owner.

## OIDC instead of stored keys

An OIDC job exchanges a short-lived token for cloud credentials. The cloud side trusts a specific issuer, audience and subject, so the credential only exists inside a workflow that matches.

- The trust policy's `sub` condition is the authorisation. `repo:ORG/REPO:ref:refs/heads/main` is one branch; `repo:ORG/REPO:*` is every branch, every pull request and every fork-run that reaches the provider.
- `repo:ORG/REPO:environment:production` binds the grant to a GitHub environment, which is where the required reviewer lives. That is stronger than a branch name, because the environment can be protected independently of the workflow file.
- Pin the audience too (`aud`), so a token minted for another service cannot be replayed.
- One role per workflow, not one role for the organisation.
- Prove the boundary: try to assume the role from an unlisted branch or a fork, and confirm it fails. A trust policy nobody tested is a guess.

See [`workload identity`](https://github.com/greenblacked/security-toolbox/blob/main/docs/gcp/index.md) for the GCP side and the [access review](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/access-review/SKILL.md) skill for auditing the trust relationships themselves.

## Runner trust

The runner is where the code executes, and its trust level decides what the workflow may do.

- **GitHub-hosted runners are ephemeral** and reset between jobs. That is the default for a reason.
- **Self-hosted runners are not.** A public repository with a self-hosted runner is untrusted code on your network: the job can read the filesystem, reach internal services, and persist between runs. If you need one, use ephemeral runners (ARC, Actions Runner Controller) with no persistent state and no network path to production.
- **Fork pull requests get a read-only token and no secrets**, and that is the property that makes public contribution safe. Anything that restores secrets to a fork-triggered job — `pull_request_target`, `workflow_run`, an environment on a fork workflow — removes it.
- **Cache and artifact poisoning**: a pull request can write a cache entry that a later run on the base branch restores. Never cache anything that is executed without a check — build outputs, binaries, `node_modules` from an untrusted lockfile change.
- **Artifacts are untrusted input.** A workflow that downloads an artifact from an earlier run and executes it has the same exposure as running the pull request's code.

## Secrets in Actions

- Repository, environment and organisation secrets are masked in logs, but only the exact value. A base64, JSON-escaped or split copy is not masked.
- Never `echo`, `set -x` with a secret in scope, or pass one as a command-line argument. `ACTIONS_STEP_DEBUG` turns on shell tracing for every step in the job.
- Prefer OIDC over a stored secret, and an environment secret over a repository secret, so the secret is only readable by a job that passed its reviewer.
- Rotate on a schedule and on exposure with the [`secret-rotation`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/secret-rotation/SKILL.md) skill. A deleted workflow run does not un-leak a secret that was printed in it.
- Enable **secret scanning with push protection** at the organisation level. It stops the commit rather than reporting it afterwards.

## Supply chain

- **Adopt a workflow dependency lockfile.** [`.github/workflows/actions.lock`](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles), generated by the `gh actions-lock` CLI extension, pins every action — **including transitive dependencies** — to a verified commit, and records the source repository's numeric `owner_id`/`repo_id` so a repointed tag or an impostor fork is rejected at run time. For a repository that adopts one, GitHub states SHA pinning inside the workflow files is no longer necessary, and the lockfile satisfies the "require SHA pinning" policy. It does not cover reusable workflows: pin those by full commit SHA.
- **Pin to a full commit SHA where no lockfile is adopted.** A tag is mutable and an action runs with your token and your network.
- **Know what SHA pinning costs you.** Dependabot only raises alerts for actions referenced by a semantic version, and will not alert on one pinned to a SHA. A repository that pins everything and does not adopt a lockfile has removed the alerting that would have told it an action was compromised — which is the argument for the lockfile, not against the pin.
- **Dependabot for `github-actions`**, so the pins and the lockfile move deliberately and in review.
- **Dependency review on pull requests** (`actions/dependency-review-action`) fails a change that adds a vulnerable or disallowed licence dependency.
- **Verify artifacts at run time.** `upload-artifact` records a SHA-256 digest and `download-artifact` recomputes and compares it, but a mismatch is a warning. Turn it into a failure in the step that consumes the artifact, or the check is advisory.
- **Build provenance attestations** (`actions/attest-build-provenance`) let a consumer verify that an artifact came from this workflow and this commit. Signing without verification is decoration; verify at the point of use.
- **Immutable releases** where the repository publishes releases: assets and tags cannot be modified after publication, and the release carries a Sigstore-format attestation.
- **Use the platform policy, not just review.** The allowed-actions policy supports explicit blocking with a `!` prefix and a "require SHA pinning" setting at repository, organisation and enterprise level — a control a contributor cannot bypass by editing a workflow.
- **Treat a new action, a new build step and a lockfile change as code.** They execute with the job's credentials and network access, and they are the part of a pull request nobody reads.

## Repository baseline

- Default branch protected by a ruleset or branch protection: pull request required, required status checks (the security gate), no force pushes or deletion, linear history if you squash.
- CODEOWNERS on `.github/`, infrastructure and policy directories.
- Secret scanning and push protection on; gitleaks in CI as a second layer that also scans history.
- Dependabot security updates plus version updates for `github-actions` and each package ecosystem, with a cooldown.
- Code scanning (CodeQL) where the plan supports it; otherwise run the same linters in CI without SARIF upload.
- Actions settings: default workflow permissions read-only; Actions cannot approve pull requests; allowed actions limited to GitHub, verified creators and an allow-list; SHA pinning required where available.
- A tag ruleset for release tags (`refs/tags/v*`; the old tag protection rules were retired in 2024 and migrated to rulesets) and environments with required reviewers and deployment branch/tag policies for production.
- `.github/workflows` is a CODEOWNERS path. A pull request that edits a workflow can grant itself any permission the workflow has, so it needs the same review as a production deploy.

## Organisation baseline

- Enforce 2FA (prefer passkeys / security keys) and SSO where available.
- Base permission `read` or `none`; access via teams.
- Restrict who can create public repositories, fork private ones, and install GitHub Apps; review installed Apps and their permissions quarterly.
- Fine-grained personal access tokens only, with approval and an expiry; prefer GitHub Apps for automation.
- Audit log streaming to your SIEM; alert on ruleset/protection changes, new deploy keys, and App installations.

## Detection and audit

The audit log is the only record of who changed the things that grant access.

| Event | Why it matters |
| --- | --- |
| `protected_branch.policy_override` / ruleset changed | Branch protection removed |
| `repo.actions_enabled` / workflow permission changed | The default that makes a forgotten `permissions` block safe is gone |
| `deploy_key.create` | A credential that bypasses branch protection |
| `personal_access_token.create` | A long-lived credential outside review |
| `org.add_member` / `team.add_member` | Access without an onboarding ticket |
| `environment.update_protection_rule` | The reviewer on production removed |
| `secret_scanning_alert.dismiss` | A leak marked as not a leak |

Stream the audit log to a store the organisation cannot edit, and alert on the rows above. GitHub's own retention is limited; an incident that starts three months ago needs your copy.

In CI, the cheapest checks are the ones that catch the mistakes above: [`zizmor`](https://github.com/woodruffw/zizmor) and `actionlint` for workflow structure and expression injection, `shellcheck` for the scripts inside `run:`, gitleaks for the tree and history, and a permission audit that fails a workflow with no `permissions:` block.

## What this repository enforces on itself

The `Security` workflow runs gitleaks over the tree and history, zizmor, ruff, CodeQL, and bash audits that fail on unpinned actions, missing top-level `permissions: {}`, missing `timeout-minutes`, and checkouts without `persist-credentials: false`.

How this repository is previewed on `stage` and released to [security.szolotov.com](https://security.szolotov.com).
