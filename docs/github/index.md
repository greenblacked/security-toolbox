# GitHub & CI

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

## Repository baseline

- Default branch protected by a ruleset or branch protection: pull request required, required status checks (the security gate), no force pushes or deletion, linear history if you squash.
- CODEOWNERS on `.github/`, infrastructure and policy directories.
- Secret scanning and push protection on; gitleaks in CI as a second layer that also scans history.
- Dependabot security updates plus version updates for `github-actions` and each package ecosystem, with a cooldown.
- Code scanning (CodeQL) where the plan supports it; otherwise run the same linters in CI without SARIF upload.
- Actions settings: default workflow permissions read-only; Actions cannot approve pull requests; allowed actions limited to GitHub, verified creators and an allow-list; SHA pinning required where available.
- A tag ruleset for release tags (`refs/tags/v*`; the old tag protection rules were retired in 2024 and migrated to rulesets) and environments with required reviewers and deployment branch/tag policies for production.

## Organisation baseline

- Enforce 2FA (prefer passkeys / security keys) and SSO where available.
- Base permission `read` or `none`; access via teams.
- Restrict who can create public repositories, fork private ones, and install GitHub Apps; review installed Apps and their permissions quarterly.
- Fine-grained personal access tokens only, with approval and an expiry; prefer GitHub Apps for automation.
- Audit log streaming to your SIEM; alert on ruleset/protection changes, new deploy keys, and App installations.

## What this repository enforces on itself

The `Security` workflow runs gitleaks over the tree and history, zizmor, ruff, CodeQL, and bash audits that fail on unpinned actions, missing top-level `permissions: {}`, missing `timeout-minutes`, and checkouts without `persist-credentials: false`.

How this repository is previewed on `stage` and released to [security.szolotov.com](https://security.szolotov.com) is in [CI & deploy](../ci.md).
