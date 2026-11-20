# CI and deploy

The website uses a hand-written homepage, shared styles and a small first-party Markdown renderer. Guide source is in `docs/`; `node scripts/build_site.cjs` writes guide routes into `site/` for deployment. It disables raw HTML and fails on unresolved local Markdown links. A local search index supports keyboard-accessible guide search at `/search/`. Install the pinned parser with `npm ci --ignore-scripts`. The pull request dry-run builds the site and checks all three Wrangler configs without Cloudflare credentials.

## Deployment paths

| Branch | Worker | Address | Trigger |
| --- | --- | --- | --- |
| `dev` | `security-dev` | https://dev.security.szolotov.com | Push to `dev` |
| `stage` | `security-stage` | https://stage.security.szolotov.com | Push to `stage` |
| `prod` | `security` | https://security.szolotov.com | Merged same-repository `stage` to `prod` pull request |

The development and staging jobs use distinct Workers, write a commit SHA to `version.txt`, and set `X-Robots-Tag: noindex` through the static asset `_headers` file. Smoke checks verify the expected revision, guide content and noindex header on the Worker's reported `workers.dev` URL. The custom domain must also be reported by Wrangler. Noindex is not access control: use Cloudflare Access if content must be private.

Production is deployed only by the merged promotion PR, not by a tag, direct push or manual dispatch. The job checks out the merge SHA and verifies that `prod` still points to it immediately before deploying. A newer push can still race that check, so protect `prod` against direct pushes and serialize promotions. The `production` GitHub environment must retain its required reviewer approval. The job records the currently active Worker version, deploys, verifies the expected commit and contents on `workers.dev`, confirms the custom domain and checks the new version serves 100% of traffic. If a later step fails after deployment begins, it attempts to roll back to the recorded version. Custom-domain requests from GitHub runners may be blocked by Bot Fight Mode, so they are informational, not the blocking smoke check.

## Credentials and GitHub environments

Create `development` and `staging` GitHub environments restricted to `dev` and `stage`, respectively. The existing repository secret `CLOUDFLARE_API_TOKEN` is used for deployments unless an optional environment-specific secret is set: `CLOUDFLARE_DEV_API_TOKEN`, `CLOUDFLARE_STAGE_API_TOKEN`, or `CLOUDFLARE_PROD_API_TOKEN`. Set `CLOUDFLARE_ACCOUNT_ID` as a repository or environment variable or secret. Retain the required reviewer on the `production` environment. The shared token must have the permissions needed for each deployment. Scope and rotate tokens as narrowly as Cloudflare supports. Tokens in the same account may still have broad Worker script authority; strict provider isolation requires separate accounts or a broker that enforces per-Worker access. Deploying custom domains requires appropriate Workers and zone permissions. Never use the global API key.

The current production environment was configured for `v*` tags with reviewer `greenblacked`; the existing `staging` environment and `stage` branch were unprotected when last inspected. These workflow changes do not alter those settings. Configure the environment branch policies for the intended deployment branches and retain production reviewer protection. Protect `stage` and `prod` with PR review, required `ci` and `security` checks, and restrictions on direct pushes, deletion and force pushes. Restrict workflow and environment administrators appropriately: a user who can change workflows, branches or environment protection can affect deployments.

## Releasing a version

Promote a tested `stage` commit through a same-repository pull request to `prod`; the merged PR triggers production deployment after environment approval. Version tags can record releases but do not trigger deployment.

## Migration and rollback

Keep `main` as the default branch during migration. Review and merge this change through the normal `main` process first, then create or update `dev`, `stage` and `prod` from the reviewed commit using controlled PRs and protections. GitHub evaluates the production workflow from the PR base branch, so `prod` must already contain the new workflow before a `stage` to `prod` promotion can run it. Verify environment rules and token permissions before triggering branch deployments. Confirm the two new domains are free and the zone/account and token scopes are correct before the first deployment. These changes create or update Workers and domain routes when the workflows run; the repository change alone does not do so.

After deployment, verify the Worker revision and status in Cloudflare, and check each domain from a client not blocked by Bot Fight Mode. If a production release fails, inspect the workflow rollback result and active version. If automatic rollback fails, use the Cloudflare dashboard or `wrangler rollback VERSION_ID --config deploy/wrangler.json --yes` with an authorised token, then verify the active version and site. Development and staging can be restored by a reviewed revert and a new branch push. Treat any restoration of the legacy tag workflow as a separate reviewed change; do not enable two production deployment paths simultaneously.

## Local checks

```bash
npm ci --ignore-scripts
node scripts/build_site.cjs "$(mktemp -d)"
python scripts/test_wrangler_helpers.py
export WRANGLER_VERSION=4.149.0
python scripts/check_wrangler_pin.py
node scripts/build_site.cjs
(cd deploy && npm ci --ignore-scripts && for config in wrangler.json wrangler.dev.json wrangler.stage.json; do ./node_modules/.bin/wrangler deploy --dry-run --config "$config" --no-autoconfig --no-install-skills; done)
```

Do not run a live Wrangler deploy from a workstation unless that upload is intended.
