# Security operations flow

Use this flow to turn security risks into controls, test whether those controls work, and carry the lessons from exercises and incidents back into everyday operations. Start at the stage that fits the situation. If there are signs of an active compromise, escalate to the incident lead before scheduling any exercise.


Use the [hands-on labs](/labs/) to practice these stages with local fixtures.

## 1. Govern and identify

Identify critical services, their owners, sensitive data, dependencies, and the harm that follows if they fail. Inventory identities, applications, endpoints, network paths and third parties across on-premises, SaaS, and cloud environments. Use a [threat model](/skills/threat-model/) and [access review](/skills/access-review/) to prioritize plausible scenarios. Record the risk owner, acceptable exposure, and the controls you expect to work.

## 2. Protect

Set baselines for authentication, privilege, endpoint and server hardening, network segmentation, application security, software supply chain, and data protection. Assign an owner to each control and document exceptions with an expiry date. Verify that teams can restore a critical service within its agreed recovery objectives. Review [host hardening](/skills/host-hardening/), [security review](/skills/security-review/), and [supply chain security](/supply-chain/).

## 3. Validate controls

Pick a specific prevention, detection, or response claim. Define expected evidence and agree who can authorize the exercise, stop it, and approve follow-up work. Use controlled, authorized assessments to collect evidence. Record findings with an owner, due date, and verification criteria. See [red, blue, and purple team responsibilities](/teams/).

## 4. Detect and investigate

Collect the telemetry required for priority scenarios. Check that identity, endpoint, application, and network events arrive with usable timestamps and context. When an alert fires, establish what happened, who and what is affected, and how confident you are. Escalate when the severity or uncertainty warrants it. See [detection engineering](/skills/detection-engineering/) and [compromise evidence preservation](/skills/compromise-evidence-preservation/).

## 5. Respond and recover

Under the incident lead, preserve relevant evidence while taking steps to limit harm. Coordinate containment, removal of the cause, and recovery with the service owner. Restore from a trusted state, test the affected controls and dependencies, and monitor for recurrence before returning to normal operations. Record major decisions, owners, and follow-up actions. See [NIST incident response recommendations](https://csrc.nist.gov/pubs/sp/800/61/r3/final).

Practice this handoff in the [incident response path](/labs/#incident-response-path).

## 6. Improve and retest

Use the incident or exercise review to revise the threat model, hardening baselines, telemetry, and response playbooks. Track accepted risks separately from verified fixes. Measure priority scenarios with working detection and response, time to escalate in controlled exercises, and whether remediation passes retesting. Review the results with risk owners and use them to choose the next validation.

This workflow draws on [NIST CSF 2.0](https://www.nist.gov/cyberframework). The functions run concurrently, and teams can validate and retest controls at any stage.
