# Detection Engineering

Build and maintain testable security detections.

## Workflow

1. Write a hypothesis describing the behavior to detect. Confirm the required source and fields are populated for the target population.
2. Version the detection rule and include an example event or fixture. Choose severity and routing based on the response required.
3. Test a representative event through the real collection and alerting pipeline, not only the rule parser. Backtest against historical logs and measure alert volume and false positives.
4. Tune with narrow, owned exceptions. Document triage steps and an owner, monitor the rule and periodically review whether it still works and earns its operational cost.

## Expected output and validation

A versioned rule, verified source fields, positive end-to-end test, backtest results, triage instructions, severity and owner. Re-test after pipeline or schema changes.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
