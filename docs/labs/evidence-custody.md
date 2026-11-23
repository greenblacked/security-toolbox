# Incident triage and evidence custody

Turn a timeline into an incident decision and verify that a working copy still matches the supplied evidence. Allow 35 minutes. Use Bash, Python 3.11 or later, and the [offline lab kit](/labs/#get-the-lab-kit).

## Check the evidence copy

From the extracted kit, run:

```bash
(
  set -eu
  lab_copy=$(mktemp -d)
  trap 'rm -rf -- "$lab_copy"' EXIT
  cp labs/fixtures/response/degraded.json "$lab_copy/events.json"
  checksum=labs/fixtures/response/degraded.sha256
  python3 labs/evidence-custody.py "$lab_copy/events.json" "$checksum"
  printf '\n' >> "$lab_copy/events.json"
  status=0
  python3 labs/evidence-custody.py "$lab_copy/events.json" "$checksum" || status=$?
  test "$status" -eq 1
)
```

The first check passes. The second detects the byte change and exits 1. The supplied digest is the exercise's baseline. In an incident, establish the digest at capture and protect it independently of the working copy. A matching digest supports integrity against that baseline. Custody records establish who handled the evidence and what they did.

## Record a triage decision

Use the degraded [telemetry timeline](/labs/response-timeline/). Record what the identity and audit evidence confirms by the cutoff, what remains unknown, and what would change the decision. Give the service owner a specific follow-up for service telemetry and the incident lead an escalation condition and review time. The missing feed leaves the service impact unresolved at the cutoff. Distinguish a confirmed role grant from a confirmed compromise.

For a simulated handoff, record the evidence ID, digest, transfer time in UTC, sender, receiver, purpose, and the receiver's verification result. Keep the original fixture as supplied. The verification command removes its temporary directory.

Continue with [service restore and recovery objectives](/labs/service-restore/). See [Compromise evidence preservation](/skills/compromise-evidence-preservation/) and [NIST forensic guidance](https://csrc.nist.gov/pubs/sp/800/86/final).
