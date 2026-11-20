# Changelog

Security Toolbox releases use Semantic Versioning. Each release uses an
annotated Git tag in the form `vX.Y.Z`. See [releasing a version](docs/ci.md#releasing-a-version).

## [Unreleased]

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
