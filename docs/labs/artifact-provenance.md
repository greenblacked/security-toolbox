# Artifact provenance gate

Verify a release signature and an independent provenance signature, then bind the artifact and SBOM to the provenance. Allow 55 minutes. Install Bash, jq, OpenSSL, and a Node.js distribution with npm that supports `npm sbom`.

## Exercise

Run the script from the [extracted lab kit directory](/labs/#get-the-lab-kit).

```bash
labs/artifact-provenance.sh
```

Read the script and trace the release key, the expected builder key, the provenance fields, and the SHA-256 digests. The release signature authenticates the file. The separate builder signature authenticates the provenance, which carries the expected build type, source, builder, artifact digest, and CycloneDX SBOM digest. The dependency-free package generates the SBOM locally with npm in offline mode.

The exercise models the verification steps with a text artifact and disposable local keys. It uses a small custom provenance record. Map the same decisions to the provenance format and trust roots used by your OCI registry and build platform before applying them in production.

## Verify and clean up

The script prints one PASS and two REJECT results. One rejection pairs a correctly signed release with provenance signed by the wrong builder. The other presents trusted provenance for a different file. Save the result lines and artifact digest as evidence. Temporary files, keys and generated metadata are removed on exit.

Related reading: [Supply chain security](/supply-chain/) and [SLSA artifact verification](https://slsa.dev/spec/v1.2/verifying-artifacts).
