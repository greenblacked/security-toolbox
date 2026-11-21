# Compromise Evidence Preservation

Preserve evidence during a suspected compromise.

## Workflow

1. Record the incident, responsible people, time and the decision to contain immediately or observe. Prioritize containment if harm is ongoing; coordinate with the incident lead.
2. Isolate without unnecessary reboot, termination or destructive cleanup. Account for autoscaling and retention that could remove evidence.
3. When safe and authorized, preserve volatile state before disk and logs, using trusted collection tooling and incident procedures. Capture snapshots and copies without modifying originals where possible.
4. Hash evidence at capture and transfer, record custody, times and storage location, protect the original and hand over a working copy to the investigation team.

## Expected output and validation

A containment decision, inventory of collected and unavailable evidence, hashes, custody record and handoff. Involve counsel when legal preservation or admissibility matters.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
