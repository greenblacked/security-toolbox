# CI and deploy

The website uses a hand-written homepage, shared styles and a small first-party Markdown renderer. Guide source is in `docs/`; `node scripts/build_site.cjs` writes guide routes into `site/` for deployment. It disables raw HTML and fails on unresolved local Markdown links. A local search index supports keyboard-accessible guide search at `/search/`. Install the pinned parser with `npm ci --ignore-scripts`. The pull request dry-run builds the site and checks the Wrangler config without Cloudflare credentials.

## Deployment paths

| Branch | Worker | Address | Trigger |
| --- | --- | --- | --- |
| `dev` | `security` preview `dev` | https://dev.security.szolotov.com | Push to `dev` |
| `stage` | `security` preview `stage` | https://stage.security.szolotov.com | Push to `stage` |
| `prod` | `security` | https://security.szolotov.com | Push to `prod`, verified as a merged same-repository `stage` to `prod` pull request |

Development and staging upload named previews of `security`, write a commit SHA to `version.txt`, and set `X-Robots-Tag: noindex` through the static asset `_headers` file. Smoke checks verify the expected revision, guide content and noindex header on the reported named `workers.dev` preview URL. The job requires Wrangler to report the expected custom preview hostname and publishes it as the environment URL. The custom hostname's version marker must return HTTP 200 directly, without redirects, and match the expected revision exactly; the job retries the check a bounded number of times. A stale response, network error, or access challenge fails the check; the hostname remains unverified until runner access and routing work. Custom hostnames require previews enabled on the production custom domain and DNS readiness; existing direct records can shadow the preview route. Verify the cutover independently before relying on these hostnames. Noindex is not access control: use Cloudflare Access if content must be private.

Production deployment is triggered by a push to `prod`. Before entering the protected environment, a job checks that the exact pushed SHA is the merge commit of a closed, merged same-repository `stage` to `prod` PR. Other pushes fail verification and do not deploy; tags and manual dispatch do not trigger this workflow. The deploy job checks out that SHA and verifies that `prod` still points to it immediately before deploying. A newer push can still race that check, so protect `prod` against direct pushes and serialize promotions. The `production` GitHub environment must retain its required reviewer approval. The job records the currently active Worker version, deploys, verifies the expected commit and contents on `workers.dev`, confirms the custom domain and checks the new version serves 100% of traffic. If a later step fails after deployment begins, it attempts to roll back to the recorded version. Custom-domain requests from GitHub runners may be blocked by Bot Fight Mode, so they are informational, not the blocking smoke check.

## Credentials and GitHub environments

Create `development` and `staging` GitHub environments restricted to `dev` and `stage`, respectively. The existing repository secret `CLOUDFLARE_API_TOKEN` is used for deployments unless an optional environment-specific secret is set: `CLOUDFLARE_DEV_API_TOKEN`, `CLOUDFLARE_STAGE_API_TOKEN`, or `CLOUDFLARE_PROD_API_TOKEN`. Set `CLOUDFLARE_ACCOUNT_ID` as a repository or environment variable or secret. Retain the required reviewer on the `production` environment. The shared token must have the permissions needed for each deployment. Scope and rotate tokens as narrowly as Cloudflare supports. Tokens in the same account may still have broad Worker script authority; strict provider isolation requires separate accounts or a broker that enforces per-Worker access. Deploying custom domains requires appropriate Workers and zone permissions. Never use the global API key.

Configure the `production` environment deployment branch policy to allow the exact branch `prod`, and retain the required reviewer. An administrator must make this setting; this workflow does not change it. Configure `development` and `staging` for their intended branches. Protect `stage` and `prod` with PR review, required `ci` and `security` checks, and restrictions on direct pushes, deletion and force pushes. Restrict workflow and environment administrators appropriately: a user who can change workflows, branches or environment protection can affect deployments.

### Production environment branch policy (required)

The Release workflow declares `environment: production` on the cloudflare job. GitHub will reject the job with:

```
Branch "prod" is not allowed to deploy to production due to environment protection rules.
```

until the environment explicitly allows the `prod` branch.

To fix:

1. Repository Settings → Environments → production.
2. Deployment branches and tags → Selected branches and tags.
3. Add the `prod` branch.
4. Keep the required reviewer to retain the approval gate.
5. Re-run the failed Release workflow.

This setting is not stored in the repository. An administrator authenticated with `gh` and authorized to manage repository environments can add and verify the exact `prod` branch rule with `jq` installed:

```bash
bash scripts/allow-production-branch.sh
```

The script requires Selected branches and tags mode, preserves existing rules and the reviewer, and fails if an API call or verification fails. It does not change the environment mode. Alternatively, use the GitHub UI above.

## Releasing a version

Promote a tested `stage` commit through a same-repository pull request to `prod`; the resulting push must pass promotion verification and production environment approval. Version tags can record releases but do not trigger deployment.

## Migration and rollback

Keep `main` as the default branch. Merge this change through the normal `main` review process, then use controlled PRs to propagate it to `stage` and `prod`. A push to `stage` before production is configured may fail its preview checks; do not rely on that preview during bootstrap. A `prod` push runs the workflow from the pushed commit, so the first same-repository `stage` to `prod` promotion must include this workflow. Verify its contents, environment rules and token permissions before merging. Approve the protected production job and verify the first production deployment before relying on stage or dev previews.

The first release cannot roll back if `security` has no previous production deployment. If the first deployment fails, inspect the live Worker and fix forward. For later releases, the job records the version serving 100% before deployment and attempts to restore that exact version if deployment checks fail. Do not deploy while traffic is split.

Enable preview traffic on the production custom domain and verify DNS and certificate readiness. Then push a reviewed revision to `stage` and subsequently `dev` to upload their named previews. Existing direct domain routes can shadow preview routing; assess and perform any DNS or route cutover separately. Removing obsolete Wrangler config files does not remove Workers, routes, or DNS records. Check the reported named workers.dev URL and each custom hostname directly: `curl -fsS https://stage.security.szolotov.com/version.txt` and `curl -fsS https://dev.security.szolotov.com/version.txt` must each equal the full SHA of the corresponding branch deployment, with no redirects. The workflow also checks HTTP 200 and exact bytes. A blocked or stale hostname is not verified.

After deployment, verify the Worker revision and status in Cloudflare, and check each domain from a client not blocked by Bot Fight Mode. If a production release fails, inspect the workflow rollback result and active version. If automatic rollback fails, use the Cloudflare dashboard or `wrangler rollback VERSION_ID --config deploy/wrangler.json --yes` with an authorised token, then verify the active version and site. Development and staging can be restored by a reviewed revert and a new branch push. Treat any restoration of the legacy tag workflow as a separate reviewed change; do not enable two production deployment paths simultaneously.

## Local checks

```bash
npm ci --ignore-scripts
node scripts/build_site.cjs "$(mktemp -d)"
python scripts/test_wrangler_helpers.py
export WRANGLER_VERSION=4.149.0
python scripts/check_wrangler_pin.py
node scripts/build_site.cjs
(cd deploy && npm ci --ignore-scripts && ./node_modules/.bin/wrangler deploy --dry-run --config wrangler.json --no-autoconfig --no-install-skills)
```

Do not run a live Wrangler deploy from a workstation unless that upload is intended.
