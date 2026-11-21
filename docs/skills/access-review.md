# Access Review

Review identities and grants against usage evidence; use an observation window long enough to cover periodic work.

## Workflow

1. Inventory people, service accounts, workload identities, CI jobs and third-party grants. Record owners, scopes, standing administrator access and break-glass identities.
2. Collect actual use and access evidence over a window that includes infrequent jobs. Separate missing evidence from proof that a permission is unused.
3. Propose smaller grants with owners and likely impact. Run an audit-only or equivalent observation phase where available, alert on would-have-denied events, and account for periodic work before enforcing.
4. Roll out reductions in stages, retain the alert, verify affected workflows and document rollback. Protect break-glass access with monitoring and review rather than removing it because it is rarely used.

## Expected output and validation

An inventory, evidence window, proposed and completed reductions, validation results, named owners and dated exceptions. Confirm expected workflows still run after enforcement.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
