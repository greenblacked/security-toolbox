# CI and deploy

The website uses a hand-written homepage, shared styles and a small first-party Markdown renderer. Guide source is in `docs/`; `node scripts/build_site.cjs` writes guide routes into `site/` for deployment. It disables raw HTML and fails on unresolved local Markdown links. A local search index supports keyboard-accessible guide search at `/search/`. Install the pinned parser with `npm ci --ignore-scripts`. The pull request dry-run builds the site and checks the Wrangler config without Cloudflare credentials.

## Deployment paths

| Branch | Worker | Address | Trigger |
| --- | --- | --- | --- |
| `dev` | `security` preview `dev` | https://dev.security.szolotov.com | Push to `dev` |
| `stage` | `security` preview `stage` | https://stage.security.szolotov.com | Push to `stage` |
| `prod` | `security` | https://security.szolotov.com | Verified release tag after a same-repository `stage` to `prod` promotion |

Development and staging upload named previews of `security`, write a commit SHA to `version.txt`, and set `X-Robots-Tag: noindex` through the static asset `_headers` file. Smoke checks verify the expected revision, guide content and noindex header on the reported named `workers.dev` preview URL. The job requires Wrangler to report the expected custom preview hostname and publishes it as the environment URL. The custom hostname's version marker must return HTTP 200 directly, without redirects, and match the expected revision exactly; the job retries the check a bounded number of times. A stale response, network error, or access challenge fails the check; the hostname remains unverified until runner access and routing work. Custom hostnames require previews enabled on the production custom domain and DNS readiness; existing direct records can shadow the preview route. Verify the cutover independently before relying on these hostnames. Noindex is not access control: use Cloudflare Access if content must be private.

A push to `prod` runs Cut release. It requires the pushed SHA to be the current `prod` HEAD and the exact merge commit of a merged same-repository `stage` to `prod` pull request. It derives the newest version and notes from `CHANGELOG.md`, creates an annotated `vX.Y.Z` tag, and explicitly dispatches Release on that tag because tags created with `GITHUB_TOKEN` do not trigger tag-push workflows. A manual Cut release dispatch on `prod` follows the same checks; an optional version must match the newest changelog entry. A retry accepts an existing annotated tag only at the same SHA and never moves it. A newer version tag blocks an older release.

Release also accepts a manually pushed tag or manual dispatch on a tag, validates the same exact promotion and current `prod` HEAD, publishes a GitHub Release with changelog notes, then enters the protected `production` environment for deployment. The Worker job repeats provenance verification and checks that `prod` has not moved immediately before deployment. Serialize promotions: a newer push can race the final check. The job builds the site and guides, records the active Worker version, deploys, verifies the commit and contents on `workers.dev`, confirms the custom domain and checks the new version serves 100% of traffic. If a later step fails after deployment begins, it attempts rollback to the recorded version. Custom-domain requests from GitHub runners may be blocked by Bot Fight Mode, so they are informational. Cut and release publication do not use Cloudflare credentials.

## Credentials and GitHub environments

Create `development` and `staging` GitHub environments restricted to `dev` and `stage`, respectively. The existing repository secret `CLOUDFLARE_API_TOKEN` is used for deployments unless an optional environment-specific secret is set: `CLOUDFLARE_DEV_API_TOKEN`, `CLOUDFLARE_STAGE_API_TOKEN`, or `CLOUDFLARE_PROD_API_TOKEN`. Set `CLOUDFLARE_ACCOUNT_ID` as a repository or environment variable or secret. Retain the required reviewer on the `production` environment. The shared token must have the permissions needed for each deployment. Scope and rotate tokens as narrowly as Cloudflare supports. Tokens in the same account may still have broad Worker script authority; strict provider isolation requires separate accounts or a broker that enforces per-Worker access. Deploying custom domains requires appropriate Workers and zone permissions. Never use the global API key.

Configure the `production` environment deployment branch policy to allow release tags matching `v*`, and retain the required reviewer. An administrator must make this setting; this workflow does not change it. Configure `development` and `staging` for their intended branches. For release tags, configure a GitHub ruleset matching `v*` to prevent tag updates and deletion while allowing the release-cutting actor to create tags. This is a recommended administrative safeguard; the workflows do not configure or verify that ruleset. Protect `stage` and `prod` with PR review, required `ci` and `security` checks, and restrictions on direct pushes, deletion and force pushes. Restrict workflow and environment administrators appropriately: a user who can change workflows, branches or environment protection can affect deployments.

## Releasing a version

Prepare a non-empty newest `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md` on `stage`, with a version greater than prior tags. Promote tested `stage` through a same-repository PR to `prod`. The resulting push cuts the tag and dispatches the release. Approve the protected production environment when prompted. If dispatch fails, rerun Cut release on `prod` or dispatch Release on the existing tag. If `prod` has moved, the older release is refused; prepare and promote the appropriate new version. Never move a release tag. A direct push, a fork PR, a non-promotion merge, or a stale tag is rejected. A tag-triggered deployment requires the workflow to exist on the tagged commit and the default branch for manual dispatch.

## Migration and rollback

Keep `main` as the default branch during migration. Review and promote changes through controlled PRs and protections. A `prod` push runs Cut release from the pushed commit; verify the workflows and tag environment policy before merging the promotion. Verify token permissions before triggering deployments. Enable preview traffic for the production custom domain and verify DNS and certificate readiness before using the custom preview hostnames. Existing direct domain routes may continue to serve the old Workers until a separately reviewed cutover. These workflows do not remove those routes.

After deployment, verify the Worker revision and status in Cloudflare, and check each domain from a client not blocked by Bot Fight Mode. If a production release fails, inspect the workflow rollback result and active version. If automatic rollback fails, use the Cloudflare dashboard or `wrangler rollback VERSION_ID --config deploy/wrangler.json --yes` with an authorised token, then verify the active version and site. Development and staging can be restored by a reviewed revert and a new branch push. Do not enable a separate branch-triggered production deployment path.

## Local checks

```bash
npm ci --ignore-scripts
node scripts/build_site.cjs "$(mktemp -d)"
python scripts/test_wrangler_helpers.py
python scripts/test_release_notes.py
export WRANGLER_VERSION=4.149.0
python scripts/check_wrangler_pin.py
node scripts/build_site.cjs
(cd deploy && npm ci --ignore-scripts && ./node_modules/.bin/wrangler deploy --dry-run --config wrangler.json --no-autoconfig --no-install-skills)
```

Do not run a live Wrangler deploy from a workstation unless that upload is intended.
