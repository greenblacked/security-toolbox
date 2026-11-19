---
name: image-hardening
description: "Build or audit hardened container images — base image selection down a scratch, distroless, Chainguard, alpine, slim ladder; digest pinning; multi-stage builds; numeric non-root UIDs; BuildKit secret and cache mounts; exec-form entrypoints; multi-arch buildx; SBOM generation; a vulnerability severity gate people will not bypass; VEX exceptions; cosign signing with admission-time verification; hadolint; and CIS Docker Benchmark plus NIST SP 800-190 as an audit structure. Use this skill whenever the user asks to write, review, shrink, harden, or fix a Dockerfile or Containerfile, choose a base image, pin or bump image digests, set up image scanning, signing or an SBOM, or asks things like \"is this Dockerfile any good\" or \"make my image smaller\". Do not use it for Kubernetes manifest authoring, host or runtime hardening, or CI work that does not produce an image."
allowed-tools: Read, Grep, Glob
---

# Image Hardening

A hardened image is a small, immutably referenced, reproducibly built artifact that carries no build tooling, no secrets, no shell it does not need, and a signed statement of where it came from — and that keeps being checked after it ships.

Adapted from greenblacked/AI plugins/security/skills/image-hardening.

## Non-negotiables (summary)

- Pin the base by digest.
- Multi-stage always.
- Numeric non-root UID (USER 65532:65532).
- No secrets in any layer (BuildKit secret mounts only).
- Exec-form ENTRYPOINT.
- Real .dockerignore.
- SBOM + scan + gate (CRITICAL/HIGH with fix blocks release).
- Sign with cosign / GitHub attestations and verify at admission.

Full ladder, Dockerfile patterns, SBOM/scan/sign commands and anti-patterns are in the original skill.
