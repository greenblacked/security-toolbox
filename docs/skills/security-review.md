# Security Review

Review a change for reachable security weaknesses.

## Workflow

1. Identify changed entry points, callers, data flows and trust boundaries, including removed checks and changed dependencies or build steps.
2. Check authorization for each affected object and operation, then examine input handling across parser boundaries, outbound requests, secret exposure and unsafe defaults.
3. Assess whether each issue is reachable and what an affected principal can do. Do not assume a route-level authentication check proves object-level authorization.
4. Write findings with evidence, impact and a concrete fix; distinguish confirmed findings from missing evidence. State the scope and what was not reviewed.

## Expected output and validation

A verdict, reviewed surface, prioritized findings with location and remediation, tests or evidence, and explicit coverage limits. Verify fixes against the affected path.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
