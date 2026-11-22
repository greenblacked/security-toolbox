# CI and deploy

> This document is not published on the site. It is the internal runbook for
> building, previewing and releasing it, and it names the credentials and
> environment settings behind those paths, so it stays in the repository.

The website uses a hand-written homepage, shared styles and a small first-party Markdown renderer. Guide source stays in `docs/`, checks and policies stay beside their code, and skill procedures are published straight from `plugins/security/skills/<name>/SKILL.md` with each `references/*.md` as a sub-page. `node scripts/build_site.cjs` renders all of it into `site/`; the generated routes are gitignored, so a local build leaves a clean tree. The renderer disables raw HTML and fails on an unresolved Markdown link, relative or absolute. A local search index supports keyboard-accessible guide search at `/search/`, and the build also writes `sitemap.xml`. Install the pinned parser with `npm ci --ignore-scripts`.

`python scripts/check_site.py site` verifies the rendered tree: every local file and anchor resolves, and every page has one `<h1>`, a `<main>` landmark, a title, a description, a canonical link and no duplicate ids. The `site check` CI job builds and runs it, so a renamed route or a heading that a table of contents links to cannot ship.

## Deployment paths

| Branch | Worker | Address | Trigger |
| --- | --- | --- | --- |
| `dev` | `security` preview `dev` | https://dev.security.szolotov.com | Push to `dev` |
| `stage` | `security` preview `stage` | https://stage.security.szolotov.com | Push to `stage` |
| `main` | `security` | https://security.szolotov.com | A `vX.Y.Z` tag cut by `Cut release`, then dispatched to `Release` |

Development and staging upload named previews of `security`, write a commit SHA to `version.txt`, and set `X-Robots-Tag: noindex` through the static asset `_headers` file. Smoke checks verify the expected revision, guide content and noindex header on the reported named `workers.dev` preview URL. The job requires Wrangler to report the expected custom preview hostname and publishes it as the environment URL. The custom hostname's version marker must return HTTP 200 directly, without redirects, and match the expected revision exactly; the job retries the check a bounded number of times. A stale response, network error, or access challenge fails the check; the hostname remains unverified until runner access and routing work. Custom hostnames require previews enabled on the production custom domain and DNS readiness; existing direct records can shadow the preview route. Verify the cutover independently before relying on these hostnames. Noindex is not access control: use Cloudflare Access if content must be private.

Production is deployed by the release workflow only, from an annotated tag. The `cloudflare` job checks out the tagged commit, refuses to deploy once `main` has moved past it, records the currently active Worker version, deploys, verifies the expected commit and contents on `workers.dev`, confirms the custom domain and checks the new version serves 100% of traffic. If a later step fails after deployment begins, it rolls back to the recorded version. Custom-domain requests from GitHub runners may be blocked by Bot Fight Mode, so they are informational, not the blocking smoke check.

`Production drift` runs daily on the default branch and compares `/version.txt` against the newest release tag, so a release that never ran cannot leave production silently stale. A 403 from the zone is reported as a notice rather than a failure, for the same Bot Fight Mode reason.

## Static headers and caching

`site/_headers` is committed and applies to production. It sets `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` and `Cross-Origin-Opener-Policy`, plus long-lived caching for the self-hosted font. The policy allows only same-origin scripts and styles, so inline `<script>` and `style=` attributes are not available: put behaviour in a file under `site/` instead. `scripts/prepare_stage_site.py` merges `X-Robots-Tag: noindex` into the existing `/*` block for previews; it does not run for production.

## Credentials and GitHub environments

Create `development` and `staging` GitHub environments restricted to `dev` and `stage`, respectively. The existing repository secret `CLOUDFLARE_API_TOKEN` is used for deployments unless an optional environment-specific secret is set: `CLOUDFLARE_DEV_API_TOKEN`, `CLOUDFLARE_STAGE_API_TOKEN`, or `CLOUDFLARE_PROD_API_TOKEN`. Set `CLOUDFLARE_ACCOUNT_ID` as a repository or environment variable or secret. Retain the required reviewer on the `production` environment. The shared token must have the permissions needed for each deployment. Scope and rotate tokens as narrowly as Cloudflare supports. Tokens in the same account may still have broad Worker script authority; strict provider isolation requires separate accounts or a broker that enforces per-Worker access. Deploying custom domains requires appropriate Workers and zone permissions. Never use the global API key.

The `production` environment is configured with reviewer `greenblacked`. These workflow changes do not alter that setting. Configure the environment branch policies for the intended deployment branches and retain production reviewer protection. Protect `stage` and `main` with PR review, required `ci` and `security` checks, and restrictions on direct pushes, deletion and force pushes. Restrict workflow and environment administrators appropriately: a user who can change workflows, branches or environment protection can affect deployments.

## Releasing a version

1. Merge reviewed work into `stage`, then promote `stage` to `main` with a same-repository pull request. `Cut release` verifies that the merge is an exact promotion and that the tree matches the recorded `stage` commit.
2. `Cut release` reads the latest `CHANGELOG.md` version, creates an annotated `vX.Y.Z` tag at `main`, and dispatches `Release` on that tag.
3. `Release` publishes the GitHub release, then deploys through the `production` environment after its required reviewer approves.

If `main` moves before `Release` runs, `Cut release` moves the still-unpublished tag to the new head on its next run. A tag that already has a published GitHub release is never moved: bump the `CHANGELOG` version instead. Never create a tag by hand as a second deployment path.

## Migration and rollback

Review and promote changes through controlled PRs and protections. GitHub evaluates a workflow from the ref it runs on, so `main` must already contain the release workflow before a tag can use it. Verify environment rules and token permissions before triggering deployments. Enable preview traffic for the production custom domain and verify DNS and certificate readiness before using the custom preview hostnames. Existing direct domain routes may continue to serve the old Workers until a separately reviewed cutover. These workflows do not remove those routes.

After deployment, verify the Worker revision and status in Cloudflare, and check each domain from a client not blocked by Bot Fight Mode. If a production release fails, inspect the workflow rollback result and active version. If automatic rollback fails, use the Cloudflare dashboard or `wrangler rollback VERSION_ID --config deploy/wrangler.json --yes` with an authorised token, then verify the active version and site. Development and staging can be restored by a reviewed revert and a new branch push. Treat any restoration of the retired `prod`-branch deployment path as a separate reviewed change; do not enable two production deployment paths simultaneously.

## Accepted dependency risks

`ecdsa==0.19.2`, pinned by `.github/requirements/checkov.txt`, carries an open
advisory: a timing side channel on P-256 (Minerva). There is no patched release.

It is accepted rather than fixed, for three reasons:

- It is reachable only through checkov's own dependency tree, in the policy-tests
  job, which runs against first-party code and pinned fixtures rather than
  untrusted input.
- The attack needs many timing measurements of ECDSA signing operations. Nothing
  in that job exposes the measurement.
- Removing it breaks the dependency that pulls it in, which is a larger change
  than the risk justifies today.

The alert is dismissed in Dependabot as `tolerable_risk`. Revisit when checkov
drops the dependency, or when `ecdsa` ships a constant-time implementation — its
own maintainers recommend the `cryptography` package for exactly that reason.

## Local checks

```bash
npm ci --ignore-scripts
node scripts/build_site.cjs
python scripts/check_site.py site
python scripts/test_wrangler_helpers.py
python scripts/test_release_notes.py
export WRANGLER_VERSION=4.166.0
python scripts/check_wrangler_pin.py
(cd deploy && npm ci --ignore-scripts && ./node_modules/.bin/wrangler deploy --dry-run --config wrangler.json --no-autoconfig --no-install-skills)
```

`WRANGLER_VERSION` must match `deploy/package.json`; the workflow pins the same value and `check_wrangler_pin.py` fails when they drift. Do not run a live Wrangler deploy from a workstation unless that upload is intended.
