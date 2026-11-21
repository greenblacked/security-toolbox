# Dependency Triage

Turn dependency alerts into risk-based decisions.

## Workflow

1. Collect and deduplicate findings by advisory, then identify affected packages, versions, dependency paths and deployed environments.
2. Assess reachability, exposure and available fixes alongside severity. Consider known exploitation and other current threat signals; treat a malicious package as an incident.
3. Choose an action per advisory: update a direct dependency, update the parent of a transitive dependency, use a supported override, mitigate, or document an exception.
4. Batch low-risk fixes behind tests, isolate changes with compatibility risk, and set an owner and expiry for each suppression. Recheck after deployment and on a regular cadence.

## Expected output and validation

A decision for each advisory with evidence, affected deployments, fix or mitigation, owner and due date. Validate the resolved dependency tree and run relevant tests.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
