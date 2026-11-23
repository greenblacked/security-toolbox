# Red, blue, and purple teams

Security exercises test a defined claim about how an organization prevents, detects, or responds to a threat. The roles below describe who owns each decision and what gets handed off. One person may cover multiple roles in a small organization.

## Red team and authorized offensive security

The red team plans and conducts an authorized assessment against agreed objectives, within written rules of engagement. A penetration test typically focuses on finding and validating weaknesses within scope. A red team exercise assesses whether people, processes, and controls meet a scenario objective. Record observations, timestamps, affected control assumptions, and impact. Hand over evidence and explain which claims were tested and what remains uncertain.

Before exercise activity begins, get written approval from the relevant owners. Record environments, permitted activity and dates, exclusions, third-party permissions, data handling, and escalation contacts. Name an exercise controller with authority to pause or stop. Pause on unexpected service impact, sensitive data exposure, an out-of-scope dependency, or signs of a real incident. Notify the controller and follow the agreed incident process. See [NIST guidance on security testing and assessment](https://csrc.nist.gov/pubs/sp/800/115/final).

## Blue team and defensive operations

The blue team owns defensive readiness, monitoring, triage, and investigation. It reviews whether the right telemetry arrived, whether alerts were useful, and whether responders could establish scope and take the right decisions. Its outputs include an incident or exercise timeline, evidence references, collection gaps, and changes to detections and playbooks. For a real incident, coordinate containment and recovery through the incident lead and the affected service owners.

## Purple team and joint validation

Purple teaming is a collaboration between the assessment and defense roles. Agree on the behavior being tested and the expected telemetry, alert, and response. Compare the red team's ground truth with what blue observed. Separate collection gaps, detection gaps, and response gaps so each goes to the right owner. Repeat the agreed scenario after fixes and record what improved. A purple team facilitator can coordinate this work without owning the controls.

## Exercise oversight and other owners

A white team or exercise controller oversees the rules of engagement, records exceptions, and has authority to stop the exercise. The controller resolves scope disputes and hands genuine incidents to incident command. Tests resume only after the designated authority clears them. See [NIST’s red team and blue team approach](https://csrc.nist.gov/glossary/term/red_team_blue_team_approach).

Application security, identity, endpoint, network, and platform teams own controls in their areas. Vulnerability management tracks findings across teams and follows up on remediation. The incident lead coordinates response and recovery. Risk and compliance teams track requirements and exceptions, and the designated risk owner decides whether to accept residual risk.

## From scope to verified fix

| Phase | Accountable role | Handoff |
| --- | --- | --- |
| Authorize | Sponsor and system owner | Signed scope, exclusions, evidence rules, and success criteria |
| Coordinate | Exercise controller | Start and stop decisions, emergency contacts, and communications plan |
| Validate | Red team and blue team leads | Timestamped observations, alerts and response decisions |
| Remediate | Control owner | Fix, due date, and evidence to collect |
| Accept residual risk | Designated risk owner | Explicit decision, rationale, and review date |
| Retest | Named validation owner | Updated control result, residual risk, and next review date |

## Example validation

In an approved test environment, use a synthetic access-denied event known to match the test detection rule to verify that an identity alert reaches the response queue. Red records the expected event and its timestamp. Blue checks whether the event was ingested, whether the alert grouped it correctly, and whether the responder could identify the test account. Purple reconciles discrepancies and schedules a replay after the owner fixes them. The exercise closes when the agreed evidence exists or the designated risk owner explicitly accepts the remaining risk.

Continue with the [security operations flow](/start/) or choose a [security domain](/about/).
