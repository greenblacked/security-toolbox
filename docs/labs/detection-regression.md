# Detection rule regression

Test an unexpected role-grant rule and a separate ingestion health check. Allow 45 minutes. Install Node.js.

## Exercise

Read the synthetic fixtures, then run the local evaluator from the [extracted lab kit directory](/labs/#get-the-lab-kit).

```bash
node labs/detection-regression.mjs labs/fixtures/detection-complete.json
node labs/detection-regression.mjs labs/fixtures/detection-missing-audit.json
```

The sample rule expects role grants to come from the audit source. The permission model allows the synthetic release bot to grant the deploy-reader role. The second check lists expected sources missing from the supplied batch.

## Verify and clean up

The complete fixture produces one alert for the temporary user and no missing sources. The release bot's expected grant produces no alert. The second fixture has no alerts and reports `audit` as missing. Record both outputs. In a live service, check the ingestion delay and collector before interpreting quiet alerts as a clean bill of health. The fixture evaluator does not measure a live ingestion SLA.

The evaluator only reads the supplied files. Delete optional fixture copies and exported output when finished.

Related reading: [Detection engineering](/skills/detection-engineering/) and [Rule record](/skills/detection-engineering/rule-record/).

Continue with [telemetry health and incident timeline](/labs/response-timeline/).
