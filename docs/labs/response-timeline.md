# Telemetry health and incident timeline

Decide whether an incident timeline has enough evidence for triage. Allow 30 minutes. Use Python 3.8 or later and the [offline lab kit](/labs/#get-the-lab-kit). Start here after the [detection regression lab](/labs/detection-regression/).

## Compare the two case files

From the extracted kit, run:

```bash
python3 labs/response-timeline.py labs/fixtures/response/complete.json
python3 labs/response-timeline.py labs/fixtures/response/degraded.json
```

Both files describe a fictional support session, approved deployment, and temporary role grant. The exercise fixes the observation cutoff at 12:10 UTC. Its example budgets are 180 seconds since the latest event and 60 seconds from event time to first observed ingestion. Records received after the cutoff are unavailable to the responder at that time. Source and event ID identify each record. Repeated deliveries retain the earliest ingestion time.

## Verify and record

The complete file has four events and all three sources are healthy. The degraded file has three events. Audit event `a-02` arrives 90 seconds after it occurred and appears once. The service source is absent at the cutoff even though its event appears in the raw data. Check that the timeline puts the two 12:07:40 UTC events in the same order when you reverse a working copy of the inputs.

Record which claim depends on the missing service event. Label equally timed events as such. Stable ordering makes output reproducible but does not establish which action happened first. A late audit entry also does not establish the cause of service errors.

The evaluator only reads its input. Delete any working copies after use. Continue with [incident triage and evidence custody](/labs/evidence-custody/).

Related reading: [Detection engineering](/skills/detection-engineering/) and [NIST incident response guidance](https://csrc.nist.gov/pubs/sp/800/61/r3/final).
