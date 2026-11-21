# IaC Review

Review a Terraform or OpenTofu change against its plan.

## Workflow

1. Use a plan artifact from a trusted pipeline and establish which workspace, state and revision it represents. Treat plan and state files as sensitive.
2. Review deletes and replacements first, especially stateful resources. Check action reasons, replacement paths, drift, moves and imports against the intended change.
3. Inspect IAM and networking changes, secrets and state exposure, provider and module pinning, policy results and cost. Confirm the plan reviewed is the plan intended for apply.
4. Record the blast radius, dependencies, recovery and rollback path, then issue a verdict with blockers and uncertainties. Validate critical assumptions with the resource owner.

## Expected output and validation

A review of the exact plan with affected resources, replacement causes, state and security risks, policy results, recovery considerations and an approve, request-changes or needs-evidence verdict.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
