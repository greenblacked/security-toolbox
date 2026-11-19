# Security plugin

Skills adapted from [greenblacked/AI](https://github.com/greenblacked/AI) `plugins/security` for platform, cloud and infrastructure security work. Each skill is a `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`); longer reference material sits in `skills/<name>/references/`.

| Skill | Use it for | Content |
| --- | --- | --- |
| `iac-review` | Terraform/OpenTofu plan review against plan JSON, blast radius first | summary |
| `image-hardening` | Dockerfile and container image hardening | summary |
| `secret-rotation` | Planned or incident credential rotation without outage or leftover copies | summary |
| `access-review` | Least-privilege review of humans, service accounts, workload identities and CI grants, judged on last-used evidence | full + references |
| `host-hardening` | Linux VM / bare-metal / bastion hardening against a named baseline without locking yourself out | full + references |
| `security-review` | Reviewing a change for the vulnerability classes actually exploited (authz, injection, SSRF, secrets, supply chain) | full + references |
| `threat-model` | Data flows, trust boundaries and STRIDE per crossing before the code exists | full + references |
| `dependency-triage` | Working Dependabot / pip-audit / govulncheck queues: reachability, EPSS, KEV, transitive fixes | full + references |
| `certificate-automation` | Moving a certificate estate to ACME / cert-manager / cloud-managed renewal | full + references |
| `detection-engineering` | Writing, testing and retiring detection rules with a hypothesis, backtest and owner | full + references |
| `compromise-evidence-preservation` | Preserving evidence from a suspected compromised host, instance, container or account before containment | full + references |

The plugin manifest sits next to the skills in this directory. The SKILL.md files can also be followed directly as written procedures.
