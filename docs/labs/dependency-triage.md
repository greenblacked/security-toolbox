# Dependency remediation queue

Build a patch queue using exploitation evidence, reachability, exposure, and service ownership. Allow 40 minutes. Use a text editor or spreadsheet. The rows below are fictional and represent a single notional snapshot.

## Exercise

| Finding | Asset and owner | Severity | In KEV | Illustrative EPSS | Exposure and reachability | Fix |
| --- | --- | --- | --- | --- | --- | --- |
| LAB-001 | Public order API, Storefront | High | Yes | 0.34 | Internet-facing, reachable | Available |
| LAB-002 | CI utility, Platform | Critical | No | 0.03 | Internal, reachability unknown | Available |
| LAB-003 | Reporting service, Analytics | High | No | 0.72 | Internal, reachable | Unavailable |
| LAB-004 | Retired image, Platform | Critical | Yes | 0.51 | Digest blocked and inventory confirms no running instances | Available |

1. Create a row per finding with priority, owner, action, due date, evidence and any exception expiry.
2. Assign a near-term verification task to every unknown. Give LAB-003 an interim control, owner and date to revisit upstream status.
3. Change the LAB-004 inventory to mark one running instance reachable from the internet. Re-score the queue and document the evidence that changed your decision.

KEV membership represents known exploitation. EPSS estimates exploitation probability over its model horizon. The numbers do not represent severity or replace local exposure and ownership evidence.

## Verify and clean up

LAB-001 should receive an urgent action. LAB-002 needs a reachability decision before accepting a deferral. LAB-003 needs an owned temporary mitigation. The changed LAB-004 scenario should escalate. Different deadlines can be valid when their assumptions and evidence are stated. Delete working copies after retaining the queue if needed.

Related reading: [Scoring signals](/skills/dependency-triage/scoring-signals/), [Reachability](/skills/dependency-triage/reachability/), [CISA KEV](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) and [FIRST EPSS](https://www.first.org/epss/).
