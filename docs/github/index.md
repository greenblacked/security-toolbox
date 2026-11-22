# GitHub & CI

The full workflow guidance is in [`checks/github/actions-hardening.md`](https://github.com/greenblacked/security-toolbox/blob/main/checks/github/actions-hardening.md): SHA pinning, minimal `GITHUB_TOKEN` permissions, `pull_request_target` risks, `persist-credentials: false`, env indirection for `${{ }}` in `run:`, and OIDC instead of long-lived cloud secrets.

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
