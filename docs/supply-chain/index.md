# Supply chain

**Who this is for:** engineers who build and ship artifacts, and the people who decide what is allowed to run in production. You should be comfortable with a container build, a lockfile and a CI pipeline.

A supply chain control answers one question: **are the bytes running in production the bytes we built, from the source we reviewed?** Everything below is a way of making that question answerable, and most of them are useless without the first one.

## Start with the digest

A tag is a mutable name. `:1.4.2` today and `:1.4.2` tomorrow can be different images, and a registry compromise or a well-meaning re-push is enough. A digest is the content:

```yaml
image: registry.example.com/app@sha256:6f1c…  # what runs
```

Pinning by digest is the cheapest control here and the only one that survives a tag rewrite. Every other control on this page assumes you know which artifact you are talking about, and a tag does not tell you. Kubernetes documents it as the baseline in its own [signed artifacts](https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/) guide.

## Provenance: what SLSA actually asks for

[SLSA](https://slsa.dev/spec/v1.2/tracks) describes how much a consumer can verify about how an artifact was built. Two things about the current version are routinely got wrong.

**There are two tracks with independent levels, not one ladder.** The build track runs L0–L3 and the source track L1–L4. You can be Source L4 and Build L1. A document that says "SLSA level 3" without naming the track has not said anything.

**The levels are about verifiability, not effort.**

| Level | What it actually guarantees | What it does not |
| --- | --- | --- |
| Build L1 | Provenance exists | It may be incomplete or unsigned. SLSA's own words: trivial to bypass or forge. It documents a process; it does not protect one |
| Build L2 | The provenance is signed by a hosted build platform | Only if the **consumer verifies it**. Signing without a verifier in the deploy path buys nothing |
| Build L3 | L2 plus build runs isolated from each other, and signing secrets unreachable by user-defined build steps | It does not defend against a malicious insider at the platform. L3 moves trust to the vendor; it does not remove it |

Source levels are the ones a small team can reach quickly: L2 is version control with history and provenance, which mostly means branch protection, no force-push, and tags that cannot be moved.

### Verification has an order, and one step is usually skipped

The [spec](https://slsa.dev/spec/v1.2/verifying-artifacts) fixes three steps: verify the envelope signature against a roots-of-trust map, check that the statement's subject digest equals the artifact's digest, and check the predicate type is `https://slsa.dev/provenance/v1`.

Two details matter more than the steps themselves:

- **An unrecognised builder defaults to L1.** If your verifier does not know the builder, it must not fall through to "trusted". Fail closed, or the map is decorative.
- **A valid signature is not a correct source.** After the signature check there is a separate expectations check: canonical repository, build type, and `externalParameters`. SLSA says any unrecognised external parameter should fail verification. Verifying the signature and stopping is the common implementation bug.

**SLSA does not cover dependency confusion or typosquatting.** Those are explicitly out of scope. Do not buy provenance as a defence against an attacker who gets you to install the wrong package; that is a registry problem, covered below.

## Signing: identity, not a key

[Sigstore](https://docs.sigstore.dev/cosign/signing/overview/) keyless signing binds a short-lived certificate to an OIDC identity, signs, and destroys the key. There is nothing to rotate and nothing to leak — the thing to protect becomes the identity that is allowed to sign.

Verification needs both of these, and omitting either is the most common misconfiguration:

```bash
cosign verify registry.example.com/app@sha256:… \
  --certificate-identity "https://github.com/ORG/REPO/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

- The **workflow path plus ref** is the security boundary. A pattern that ends in `@*` accepts a signature from any branch, which is not the control you meant.
- GitHub Actions' issuer is `https://token.actions.githubusercontent.com`. The issuer for interactive GitHub OAuth is different (`https://github.com/login/oauth`), and using the wrong one fails open in a way that is hard to notice.
- A ten-minute certificate is fine only because the signature carries a **timestamp**; verification checks that the timestamp falls inside the certificate's validity window. If your verifier has no timestamp source, old signatures become unverifiable.
- Sigstore is explicit about what it does not guarantee: an OIDC provider or Fulcio compromise is detectable only through the transparency log, and **if nobody monitors the log, misbehaviour may go undetected**. Watching it is your operational job, not theirs.
- Offline or registry-outage verification needs a bundle (`cosign bundle create`) holding the certificate, signature, timestamps and attestations. Decide that before you need it.

## GitHub: attestations, releases and cache

[Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations) generate signed provenance for an artifact. Out of the box that is **SLSA Build L2**. To reach **L3** the build has to run inside a reusable workflow, which is what provides isolation between the build and the caller — it is a documented path, not an inference.

```yaml
permissions:
  id-token: write        # signing identity
  contents: read
  attestations: write    # the attestation itself
```

Two things to know before relying on it:

- **Public and private repositories are not equivalent.** A public repository writes the bundle to GitHub *and* to an immutable public transparency log. A private repository uses GitHub's own Sigstore instance, which has **no transparency log**. If audit is the reason you are doing this, that difference matters.
- **The attestation is bound to the digest, but `gh attestation verify` accepts a tag for images.** Pin the digest yourself rather than letting the tag choose what you verify.

[Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) close the "retag the release with a backdoor" gap: once published, assets and the tag cannot be modified or deleted, the tag name cannot be reused, and the release carries a generated attestation. Draft the release, attach every asset, then publish.

**The Actions cache is a supply-chain surface.** Caches are not signed or verified. GitHub restricts write access to the default-branch scope for low-trust triggers (`pull_request_target`, `issue_comment`, `workflow_run`), and a `cache-mode: write` on one of those re-introduces cache poisoning. If a workflow sets it, that is a finding, not a performance tweak.

## Dependencies: harden the install path

Most supply-chain incidents arrive at install time, not at build time. The scanner runs after the code has already executed.

- **Commit the lockfile and install from it.** `npm ci`, `pip install --require-hashes`, `go mod verify`.
- **Restrict where a package may come from.** npm supports `--allow-git=none` and `--allow-remote=none`, in `.npmrc` as well as on the command line, which removes the git and remote-tarball install paths entirely.
- **Stage the publish, do not publish.** npm's staged publishing puts a tarball in a queue that a human must approve with a 2FA challenge, and a trusted publisher can be restricted to stage-only so a stolen CI token cannot publish at all. That is the practical answer to "the token was stolen and shipped malware".
- **A registry firewall is better than a faster scanner.** GitHub's package firewall (public preview, npm only, Enterprise Cloud) inspects metadata and downloads between your runners and the upstream registry, with a cooldown period, an advisory check, and detection of attestation downgrades. Preview means exactly that: evaluate it, do not depend on it.

## SBOM: what it is, and what it is not

An SBOM is an inventory. [SPDX 3.0](https://spdx.dev/use/specifications/) and [CycloneDX 1.7](https://cyclonedx.org/specification/overview/) are the two current formats, and the choice matters less than binding the result to a digest — an unsigned SBOM is a claim about a possibly different build.

Attach it to the artifact rather than filing it somewhere: a GitHub attestation can carry the SBOM as a predicate, so the inventory is bound to the same digest as the provenance.

| What an SBOM cannot do | Why |
| --- | --- |
| Tell you whether anything is vulnerable | It is an inventory; risk needs a vulnerability feed joined to it |
| Tell you whether a vulnerability is exploitable | That needs VEX and reachability analysis, which are separate artifacts |
| Tell you how the artifact was built | That is provenance. The two are routinely conflated |
| Prove it describes the artifact in front of you | Without a digest-bound signature it describes some other build |
| See what is not declared | Vendored copies, static linking, runtime plugins, base images pulled later, SaaS internals |
| Detect a well-formed malicious package | A typosquat or a compromised release looks like a normal dependency |
| Assert its own completeness | CycloneDX models this honestly: `compositions` may be `incomplete`, `incomplete_first-party-only`, `incomplete_third-party-only` or `unknown` |

That last row is worth acting on: treat `compositions: unknown` as a finding, because the format is telling you the inventory is partial.

## Enforce it at admission

Verification that only runs in CI is a report. The gate is the admission path:

- **Digest-pinned manifests** everywhere, so a tag cannot change what a running pod is.
- **Binary Authorization** on GKE binds attestations to the image's registry path and digest, blocks deployment when the policy fails, and writes the reason to Cloud Audit Logs — which makes a denial a detection signal as well as a gate. Its continuous re-validation of running pods is still in preview, so post-admission drift is not covered by the GA path.
- Kubernetes recommends the sigstore policy-controller for verifying non-control-plane images at admission where you are not on GCP.

## What to do first

1. **Pin by digest, and verify at admission.** Nothing else works if you cannot say which bytes you are running.
2. **Attest inside a reusable workflow.** Three permissions and one step, and it is the shortest documented route to Build L3.
3. **Turn on Data Access audit logs, sink them to a locked bucket, and exclude development.** Admin Activity is already on and free; Data Access is the blind spot. See [GCP](/gcp/).
4. **Harden the install path rather than the scanner.** Lockfiles, `--allow-git=none`, staged publishing.
5. **Ship the SBOM as a signed predicate, not a PDF.** A detached file proves nothing about what is deployed.

## Next

- [Kubernetes](/kubernetes/) — images, digests and admission on the cluster.
- [GitHub Actions](/github/) — the workflow that does the building.
- [Dependency Triage](/skills/dependency-triage/) — working the alert queue an SBOM and a scanner produce.
- [Glossary](/glossary/) — provenance, SBOM, SLSA, digest.

## Hands-on lab

Practice locally in the [Artifact provenance gate](/labs/artifact-provenance/) lab.
