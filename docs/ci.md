# CI and deploy

This repository has two required GitHub Actions checks on `main`: `ci` and `security`. They are unchanged here. Site deploys are a separate path, modelled on [greenblacked/AI](https://github.com/greenblacked/AI): one Worker, two environments, no credential on a pull request.

The Worker is `security` in `deploy/wrangler.json`. Production is [https://security.szolotov.com](https://security.szolotov.com). The homepage Cloudflare serves is the hand-written file `site/index.html`. MkDocs builds documentation into `build/docs`. Before the Wrangler dry-run, preview upload or release, `scripts/package_worker_site.py` adds the generated guides and assets to the runner’s `site/` directory and preserves the hand-written homepage.

## `.github/workflows/deploy.yml` — dry-run and stage

Runs on every pull request, on a push to `stage`, and on `workflow_dispatch`. Top-level `permissions: {}`. Neither job grants itself more than `contents: read`. Not a required check.

| Job | Check name | Failing means |
| --- | --- | --- |
| `dry-run` | `dry-run deploy` | The Wrangler pin disagreed with `deploy/package-lock.json`, or `wrangler deploy --dry-run` rejected the Worker. No credential is read. The job does not run on `workflow_dispatch`. |
| `preview` | `preview` | The run was not from `stage`, the Cloudflare credential was missing, `wrangler preview` failed or reported no acceptable URL, or the live `workers.dev` preview failed a smoke check. A Preview has no rollback and production is not touched, so the job stays red until the next push. The job does not run on a pull request. |

`dry-run` is the pull request. It asks Wrangler to compile the Worker without uploading it. `--no-autoconfig` and `--no-install-skills` are named because Wrangler 4's defaults would otherwise detect a framework and can install agent skills into the checkout. The install is `npm ci --ignore-scripts` from the lockfile, after `scripts/check_wrangler_pin.py` has required `WRANGLER_VERSION` to be the version both `deploy/package.json` and the lockfile declare, with a sha512 integrity on the wrangler tarball.

`preview` runs on a push to `stage`, and on Run workflow from that branch only. Its first step refuses any other ref. It runs `scripts/prepare_stage_site.py`, which writes `site/_headers` with a `/*` rule setting `X-Robots-Tag: noindex` and leaves `site/index.html` unchanged. It does not write a `robots.txt` that would block crawling: a `Disallow: /` would stop crawlers from seeing the header, which is the signal that actually prevents indexing. If an untracked leftover `robots.txt` is present, the script removes it. If a tracked `site/_headers` is added later, the script appends the noindex rule instead of overwriting the file.

Cloudflare documents that a `_headers` file in the [static asset directory](https://developers.cloudflare.com/workers/static-assets/binding/#directory) is parsed and applied to static asset responses ([Headers](https://developers.cloudflare.com/workers/static-assets/headers/)). That is `site/`, the directory `deploy/wrangler.json` sets as `assets.directory`. [Protect Preview content](https://developers.cloudflare.com/workers/previews/custom-domains/#protect-preview-content) says Cloudflare adds `X-Robots-Tag: noindex` automatically to `workers.dev` Preview URLs, but not to custom-domain Preview URLs, and that for static assets the header should be added through a `_headers` file. The [Pages migration guide](https://developers.cloudflare.com/workers/static-assets/migration-guides/migrate-from-pages/) (in the section that describes preview builds, which run `wrangler preview`) says `_headers` is supported natively in Workers with static assets when the file is included in the static asset directory. The Headers page itself does not mention `wrangler preview` by name; the Preview documentation above is the statement that custom-domain Previews should use `_headers` for this header.

Then, after the same pin check and `npm ci --ignore-scripts` — and only after those, so no install script sees the token — it runs `wrangler preview --config wrangler.json --name stage --no-install-skills`. That uploads this commit as a Preview of the one Worker `security`. A Preview is a separate version that Cloudflare serves at its own URL: `https://stage.security.szolotov.com` once the custom domain `security.szolotov.com` has Preview traffic enabled, and a `workers.dev` Preview URL besides. Production traffic keeps running the version the last tag deployed; uploading a Preview does not change it, and a Preview has no rollback because there is nothing to roll back to.

`wrangler preview` does not attach custom domains. Routes, including `previews_enabled`, come from `wrangler deploy` (the first release applies `deploy/wrangler.json`) or from the dashboard. If the Worker does not exist yet, `wrangler preview` creates it first, with `workers.dev` on and no custom domain or production deployment, so a Worker appearing after a push to `stage` is that and not a stray production deploy.

`scripts/read_wrangler_deploy.py --preview` reads the `preview` line Wrangler writes to `WRANGLER_OUTPUT_FILE_PATH` and keeps a URL only when it is `https`, with no user, port, path or query, on a `workers.dev` host or at or below `security.szolotov.com`. The job smoke-tests the site, guide routes, and search index on the reported `workers.dev` preview. It verifies that `/version.txt` matches the deployed commit, then publishes the tested URL to the GitHub staging environment. If Wrangler does not report `https://stage.security.szolotov.com`, the job emits a warning. The custom address requires Preview traffic to be enabled on the Cloudflare custom domain.

## `.github/workflows/release.yml` — production

Runs on a pushed `vX.Y.Z` tag, and on `workflow_dispatch` pointed at such a tag. Top-level `permissions: {}`. The `cloudflare` job grants itself `contents: read` only. A dispatch on a branch is refused by the first step, which requires `$GITHUB_REF_TYPE` to be `tag` and `$GITHUB_REF_NAME` to match `v[0-9]+.[0-9]+.[0-9]+`. The tagged commit must be an ancestor of `origin/main`.

The job installs the same pinned Wrangler, after the pin check and `npm ci --ignore-scripts`, then:

1. Reads the version production is serving with `wrangler deployments status --json`, through `scripts/read_wrangler_deploy.py --active`, so a later failure can roll back to exactly that version. A first release, when the Worker has no deployments yet, warns and continues with nothing to roll back to.
2. Runs `wrangler deploy --config wrangler.json --no-autoconfig --no-install-skills`.
3. Requires Wrangler to report `https://security.szolotov.com` and a `workers.dev` address. `workers_dev` in `deploy/wrangler.json` must stay `true`: that address is how the release is smoke-tested. Before the deploy, the job writes `site/version.txt` on the runner with the tag (it is not committed). `scripts/smoke_site.sh` fetches the `workers.dev` URL, requires HTTP 200 and the expected content on the homepage, guide routes, and search index, and requires `/version.txt` to serve that same tag. The custom domain is not fetched as a blocking check; Bot Fight Mode on the zone can answer a GitHub runner with HTTP 403, and no WAF rule can skip it.
4. Confirms `wrangler deployments status --json` shows the version just deployed serving all traffic (`--active-is`).
5. Logs the HTTP status of `https://security.szolotov.com/` as a notice when it is 403, and never fails the job for that.
6. On failure after a deploy started, rolls back to the version recorded in step 1.

## Credentials and GitHub environments

`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are repository secrets, with optional `vars.CLOUDFLARE_ACCOUNT_ID` as a fallback, as chosen for this repository. The dry-run job never names them. The preview job runs only from `stage`, in the `staging` environment. The release job runs only on a `vX.Y.Z` tag, in the `production` environment. Environment secrets, if added later, would be preferred by GitHub for those jobs.

A pull request from this repository can read a repository secret by editing a workflow and naming the secret, which is the trade-off of keeping the token at repository level. Fork pull requests cannot. The dry-run job is written so that a pull request cannot read the token from a step that already holds it, because no step there holds it.

Optional variable `DEPLOY_URL` on the production environment is an `https` origin with no path, shown as the environment's deployment link. It is not smoked.

## GitHub and Cloudflare settings

### Current GitHub settings

These are already in place:

- The `staging` environment exists and has no protection rules and no deployment branch policy (no reviewers, no wait timer, no branch restriction).
- The `stage` branch exists at `56ddc56` and is unprotected: no ruleset, force pushes and deletion are not blocked by a ruleset on that branch.
- The `production` environment admits only `v*` tags, requires reviewer `greenblacked` (`prevent_self_review` is off), and has no wait timer.

### Optional hardening

The following would tighten who can run a job that holds the Cloudflare token. They are not configured today. Applying them needs Creator's approval; this change does not apply them.

- Restrict the `staging` environment to the `stage` branch only (Selected branches).
- A branch ruleset targeting `stage` that requires a pull request, requires the `ci` and `security` status checks, and blocks force pushes and deletion. Anyone who can push to `stage` gets a job that holds the Cloudflare token, and with one Worker that token can also deploy production: it is the same Worker, and the token's scope is the account and zone, not an environment.

### Cloudflare dashboard

These remain dashboard steps, before the first tag or the first push to `stage` that should succeed:

1. In the Cloudflare dashboard, open **My Profile → API Tokens → Create Token** (or **Manage Account → Account API Tokens**). Start from the **Edit Cloudflare Workers** template. Scope **Account resources** to the one account and **Zone resources** to the active `szolotov.com` zone in the same account. The token needs **Account / Workers Scripts / Edit**, and on the zone **Zone / Zone / Read**, **Zone / DNS / Edit** and **Zone / Workers Routes / Edit**: `wrangler deploy` creates the custom domain `security.szolotov.com` with its DNS record and certificate. Keep **Account / Workers Tail / Read**, **Account / Account Settings / Read** and the user membership read the template includes; `wrangler deploy` and `wrangler rollback` call them. The template's Workers KV and R2 permissions are unused here and can be removed if the form allows. Validate the grants with a real deploy rather than narrowing them from documentation alone. Do not use the account's Global API Key. Set an expiry you will actually rotate. Whether the same token also covers Previews should be confirmed in the dashboard, not assumed from this list.
2. Copy the **Account ID** from the Workers overview, or from the URL when the account is open. It is not a secret. It still should not be committed.
3. Open **Workers & Pages → `security` → Settings → Domains & Routes** and enable `security.szolotov.com` for **Production and Preview**, or let the first release apply `deploy/wrangler.json`, whose route sets `previews_enabled`. Until one of the two is done, `stage.security.szolotov.com` does not answer and the `preview` job fails with an error that says so. Delete any `stage.security` DNS record created by hand: Cloudflare serves a Preview named `stage` from the domain's Preview wildcard, and a record of the same name would shadow it. Putting the stage Preview behind Cloudflare Access, and any custom-domain or DNS work that goes with that, is also a dashboard step.
4. Leave Bot Fight Mode on, and keep `workers_dev` and `preview_urls` set to `true` in `deploy/wrangler.json`. The release check goes through `workers.dev` and fails when Wrangler reports no such address. `preview_urls: false` would block the stage Preview.

## Local checks

From the repository root, with Wrangler installed from `deploy/package-lock.json`:

```bash
export WRANGLER_VERSION=4.149.0
python scripts/check_wrangler_pin.py
python scripts/test_wrangler_helpers.py
# Confirm site/index.html is the hand-written homepage and is not overwritten:
mkdocs build --strict --site-dir "$(mktemp -d)"
test -z "$(git status --porcelain --untracked-files=no -- site/index.html)"
(cd deploy && npm ci --ignore-scripts && ./node_modules/.bin/wrangler deploy --dry-run --config wrangler.json --no-autoconfig --no-install-skills)
```

Do not run `wrangler deploy` or `wrangler preview` against the account from a workstation unless that upload is intended.
