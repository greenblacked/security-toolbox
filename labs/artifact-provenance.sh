#!/usr/bin/env bash
set -Eeuo pipefail

lab_dir=$(mktemp -d)
trap 'rm -rf -- "$lab_dir"' EXIT
cd -- "$lab_dir"
export npm_config_cache="$lab_dir/npm-cache"
umask 077

printf '%s\n' '{"name":"security-toolbox-lab-artifact","version":"1.0.0","license":"MIT"}' > package.json
npm install --package-lock-only --ignore-scripts --offline --no-audit --no-fund > /dev/null
npm sbom --sbom-format cyclonedx --package-lock-only --offline > sbom.json
printf '%s\n' 'Security Toolbox sample release artifact' > artifact.txt

digest() {
  openssl dgst -sha256 -r "$1" | cut -d ' ' -f 1
}
sign() {
  openssl dgst -sha256 -sign "$1" -out "$2" "$3"
}
verify_signature() {
  openssl dgst -sha256 -verify "$1" -signature "$2" "$3" > /dev/null 2>&1
}

for identity in release builder other-builder; do
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$identity.key" 2> /dev/null
  openssl pkey -in "$identity.key" -pubout -out "$identity.pub"
done

jq -n --arg artifact "$(digest artifact.txt)" --arg sbom "$(digest sbom.json)" '{
  artifactSha256: $artifact, sbomSha256: $sbom, builder: "offline-lab-builder",
  source: "security-toolbox-lab", buildType: "offline-text-release"
}' > provenance.json
sign release.key artifact.sig artifact.txt
sign builder.key provenance.sig provenance.json
sign other-builder.key untrusted.sig provenance.json

verify_provenance() {
  verify_signature builder.pub "$1" provenance.json || return 1
  jq -e --arg artifact "$(digest "$2")" --arg sbom "$(digest sbom.json)" '
    .artifactSha256 == $artifact and .sbomSha256 == $sbom and
    .builder == "offline-lab-builder" and .source == "security-toolbox-lab" and
    .buildType == "offline-text-release"
  ' provenance.json > /dev/null
}

verify_signature release.pub artifact.sig artifact.txt
verify_provenance provenance.sig artifact.txt
printf '%s\n' 'PASS: release signature, trusted provenance, artifact digest and SBOM digest'

if verify_provenance untrusted.sig artifact.txt; then
  echo 'Unexpectedly accepted provenance from an untrusted signer' >&2
  exit 1
fi
printf '%s\n' 'REJECT: valid release signature paired with untrusted provenance'

printf '%s\n' 'Different sample artifact' > different.txt
if verify_provenance provenance.sig different.txt; then
  echo 'Unexpectedly accepted provenance for a different artifact' >&2
  exit 1
fi
printf '%s\n' 'REJECT: trusted provenance for a different artifact'
jq -r '"Artifact SHA-256: " + .artifactSha256, "Builder: " + .builder' provenance.json
