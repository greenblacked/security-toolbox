# Security domains

Start with the business service or security outcome you need to protect. Most investigations and exercises cross several domains, so identify dependencies and owners as you go.

Learn how the guides, checks, and exercises fit together in the [project story](/story/).

## Identity, endpoints, and networks

- **Identity:** review privileged access, joiner and leaver processes, service identities, strong authentication, and emergency access. Use [access review](/skills/access-review/) and [secret rotation](/skills/secret-rotation/).
- **Endpoints and servers:** verify managed inventory, patch coverage, disk protection, endpoint telemetry, and recovery from a trusted baseline. Use [host hardening](/skills/host-hardening/).
- **Networks:** inventory internet exposure, verify segmentation and administrative access, and confirm that logs cover critical boundaries. Record temporary exceptions and escalation contacts.

## Applications, delivery, and data

- **Applications and APIs:** map trust boundaries, test access control under authorization, and review sensitive inputs, dependencies, and logging. Start with [threat modeling](/skills/threat-model/) and [security review](/skills/security-review/).
- **Build and delivery:** isolate build identities, scope credentials, and validate artifact integrity. See [supply chain security](/supply-chain/), [GitHub Actions](/github/), and [GitLab runner isolation](/gitlab/).
- **Data and recovery:** classify sensitive data, limit collection and access, review retention, and test backup restoration with service owners.

## Infrastructure and cloud

Review configuration, change controls, segmentation, and secrets across on-premises systems, SaaS, and cloud services. For platform-specific checks, see [Kubernetes](/kubernetes/), [Google Cloud](/gcp/), [Terraform](/terraform/), and [Cloudflare Workers](/cloudflare/).

## Security operations and assurance

Use the [security operations flow](/start/) to connect prevention and detection to incident response and recovery. For authorized assessments, exercises, and retests, clarify [red, blue, and purple team responsibilities](/teams/) before work begins.
