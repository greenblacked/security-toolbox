# Image Hardening

Review container builds and image security.

## Workflow

1. Choose a maintained base appropriate to the application and pin it by digest. Minimize installed packages and use a multi-stage build to exclude build tooling from the runtime image.
2. Run as a numeric non-root user where practical, use an exec-form entrypoint, and keep credentials out of layers and build context. Use secret mounts when builds require secrets.
3. Generate an SBOM, scan the built artifact and handle findings with a documented, owned exception process. Sign the artifact and verify its identity before deployment where supported.
4. Test startup and application behavior under the intended runtime restrictions, including filesystem and permissions. Rebuild and re-scan when the base or dependencies change.

## Expected output and validation

An image pinned by digest, build and runtime checks, SBOM, scan results, signing and verification evidence, plus owners and expiry dates for exceptions.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
