# Changelog

Security Toolbox releases use Semantic Versioning. Each release uses an
annotated Git tag in the form `vX.Y.Z`. See [releasing a version](docs/ci.md#releasing-a-version).

## [Unreleased]

### Added

- Publish the full security skill procedures at `/skills/`, including each
  `references/*.md` file, instead of eleven-line summaries. `docs/skills/` is
  removed; `plugins/security/skills/` is now the only source.
- Group the guide navigation by section, mark the current page, and add a
  breadcrumb, previous/next links, an "Edit this page" link and a last-updated
  date to every guide page.
- Ranked search with section deep links, snippets, match highlighting, an empty
  state and a `/` shortcut.
- `sitemap.xml`, a favicon, canonical URLs, Open Graph and Twitter metadata, and
  per-page descriptions taken from each page's own opening paragraph.
- `site/_headers` for production: a same-origin Content Security Policy plus
  `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
  `Permissions-Policy`, `Cross-Origin-Opener-Policy` and font caching.
- `scripts/check_site.py`, which verifies every local file and anchor plus the
  head and landmark structure of each page, and runs in CI.
- `Production drift`, a daily job that compares the production `version.txt`
  against the newest release tag.
- An About page and an `about/` route for the repository overview.

### Changed

- `Cut release` moves a tag that is still unpublished to the current `main` head
  instead of failing. A tag cut before the last promotion merged left production
  on the previous release with no way to catch up.
- Bring the release pipeline on `dev` back in line with `main`: the tag-triggered
  release, `Cut release`, `scripts/release_notes.py` and its tests, and the
  `0.1.1` changelog entry. Promoting `dev` would otherwise have reverted them.
- Rewrite `docs/ci.md` for the tag-triggered release and correct the documented
  `WRANGLER_VERSION`, which did not match `deploy/package.json`.
- Replace the placeholder "site HTML is valid enough" CI job and the separate
  docs job with one job that builds the site and checks it.

### Fixed

- Code blocks no longer break a URL or identifier across two lines; they scroll
  instead.
- The stored light theme is applied before the first paint, so it no longer
  flashes the dark palette.
- Reduce the empty band above the homepage headline.
- Give the access-review comparison table a header for its first column.

## [0.1.1] - 2026-11-20

### Changed

- Refresh the documentation site with platform guide navigation, a copyable
  read-only Kubernetes quickstart, warm Light and Dark themes, and responsive layouts.
- Add a self-hosted Instrument Sans font and license, stronger control borders,
  and underlined links in guides.
- Promote tested changes from development through staging to production on main,
  with exact promotion and release tree verification.

## [0.1.0] - 2026-11-20

### Added

- Initial Security Toolbox release with read-only GKE and Kubernetes workload
  reports, Terraform and Kubernetes Conftest policies, and custom Checkov rules
  for Google Cloud.
- Hardening guides for Kubernetes and GKE, Google Cloud, Terraform, GitHub
  Actions, and secrets, with searchable documentation.
- A redesigned homepage with a Kubernetes quickstart, guide navigation, a
  checks and policies index, and access to the security skills catalog.
- Cloudflare staging previews and tagged production deployments with revision
  verification and rollback when a previous production version is available.

### Fixed

- Package the generated documentation with the homepage so all guide links
  resolve, including `/kubernetes/`.
- Wait for the new Worker revision to propagate before smoke-testing the
  homepage, documentation routes, search index, stylesheet, and theme script.
