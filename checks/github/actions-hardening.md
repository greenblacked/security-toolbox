# GitHub Actions hardening

A workflow is code that runs with your repository's credentials. Treat every change to `.github/workflows/` as a privileged change. This repository's own `security.yml` enforces several of the items below on every push (SHA pinning, top-level `permissions: {}`, `timeout-minutes`, `persist-credentials: false`, zizmor, gitleaks).

## 1. Pin every action to a full commit SHA

Tags and branches are mutable; a compromised or retagged action runs with your token. Pin to the 40-character SHA and keep the version in a comment so Dependabot can update it:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
```

- Enable Dependabot for `github-actions` with a cooldown so new releases age a few days before you adopt them.
- Prefer actions from GitHub, the tool vendor, or your own org. Read the `action.yml` and what it downloads before adding a new one.
- Pin container images in `container:` / `services:` and `docker://` steps by digest too.
- The org/repo setting that requires actions to be pinned to a full-length commit SHA enforces this server-side where your plan allows it.

## 2. Grant the minimum `GITHUB_TOKEN` permissions

```yaml
permissions: {}            # top level: nothing by default

jobs:
  build:
    permissions:
      contents: read       # only what this job needs
```

- Set the repository/org default workflow permission to read-only.
- Grant `write` scopes (`contents`, `packages`, `id-token`, `pull-requests`, `security-events`) per job, never at the top level, and only on jobs that do not run untrusted code.
- Disable "Allow GitHub Actions to create and approve pull requests" unless a workflow truly needs it.

## 3. `pull_request_target` and `workflow_run` are privileged

`pull_request_target` runs in the context of the base branch with a read/write token and access to secrets, even for pull requests from forks. The classic compromise is checking out and executing the PR's code in that context:

```yaml
# DANGEROUS: runs attacker-controlled code with secrets
on: pull_request_target
jobs:
  test:
    steps:
      - uses: actions/checkout@<sha>
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - run: npm ci && npm test
```

- Use `pull_request` for anything that builds or tests PR code; for forks it gets a read-only token and no secrets.
- If you need `pull_request_target` (labelling, triage), never check out or run the head ref, and keep permissions to the specific write scope.
- The same applies to `workflow_run` jobs that download artifacts produced by a PR: treat the artifact as untrusted input.
- Protect deploy secrets with environments that have required reviewers and branch/tag deployment policies.

## 4. `persist-credentials: false` on checkout

`actions/checkout` stores the token in `.git/config` by default, where any later step (or a dependency's install script) can read it, and where uploading the workspace as an artifact can leak it.

```yaml
- uses: actions/checkout@<sha>
  with:
    persist-credentials: false
```

If a later step must push, give the token to that one step only (for example a one-off `http.extraheader`, or `GH_TOKEN` in that step's `env:`).

## 5. Never interpolate untrusted `${{ }}` into `run:`

Expressions are expanded into the script text before the shell runs, so a PR title, branch name, issue body or commit message containing shell syntax becomes code.

```yaml
# Vulnerable
- run: |
    echo "Title: ${{ github.event.pull_request.title }}"

# Safe: pass through the environment and quote it
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: |
    echo "Title: $PR_TITLE"
```

Attacker-controllable fields include `github.event.pull_request.title`, `.body` and `.head.ref`, `github.event.issue.title` and `.body`, `github.event.comment.body`, `github.head_ref` and commit messages. The same applies to `actions/github-script` `script:` blocks. Moving even trusted values (`needs.*.result`, `inputs.*`) into `env:` keeps the pattern consistent and zizmor's pedantic audit quiet.

## 6. Prefer OIDC to long-lived cloud secrets

Instead of storing a cloud key as a repository secret, let the job exchange its OIDC token for short-lived credentials:

```yaml
permissions:
  contents: read
  id-token: write          # only on the deploy job

steps:
  - uses: google-github-actions/auth@<sha>  # vX
    with:
      workload_identity_provider: projects/123456789/locations/global/workloadIdentityPools/github/providers/github
      service_account: deployer@my-project.iam.gserviceaccount.com
```

- On GCP, restrict the Workload Identity provider with an attribute condition on `assertion.repository` (and `assertion.ref` or the environment) so other repositories cannot use it.
- AWS (`aws-actions/configure-aws-credentials` with `role-to-assume`) and Azure (`azure/login` with federated credentials) work the same way; scope the trust policy to repository plus branch or environment.
- Delete the old static keys once OIDC works. The Terraform policies in `policies/` deny `google_service_account_key` for this reason.

## 7. Everything else that matters

- `timeout-minutes` on every job, so a hung or abused job does not burn hours.
- Self-hosted runners: never on public repositories; ephemeral runners only; no runner shared between trust levels.
- Caches written on the default branch are readable from PR runs; never cache secrets or outputs you later trust for releases.
- Branch protection or rulesets requiring the security gate, plus CODEOWNERS on `.github/`.
- Run [zizmor](https://github.com/zizmorcore/zizmor) and [actionlint](https://github.com/rhysd/actionlint) on every workflow change.

## Quick audit

```bash
# Unpinned actions
grep -nE '^\s*(- )?uses: [^@]+@' .github/workflows/*.y*ml | grep -vE '@[0-9a-f]{40}(\s|$)'
# pull_request_target / workflow_run triggers worth a closer look
grep -nE 'pull_request_target|workflow_run' .github/workflows/*.y*ml
# Expressions from event payloads (review each hit inside run: blocks)
grep -nE '\$\{\{\s*github\.(event|head_ref)' .github/workflows/*.y*ml
# Full audit
zizmor --persona=regular --min-severity=medium .
```
