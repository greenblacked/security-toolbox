# CI identity claims

Practice defining a workload identity trust condition for a synthetic GitHub repository and a synthetic GitLab project. Allow 40 minutes. Install Node.js.

## Exercise

1. Read `labs/fixtures/ci-identity.json`. For each provider, identify the issuer, audience, stable identity, and approved deployment context.
2. Run the evaluator and explain how a failed condition changes the decision.

```bash
node labs/ci-identity.mjs
```

3. In a disposable copy of the repository, add a GitLab case with the expected audience and branch but a different project ID. Predict the decision, rerun the evaluator, and compare.

The evaluator assumes synthetic claims have already been decoded. A production relying party must verify token authenticity, issuer, audience, expiry, and other protocol requirements before applying its provider-specific policy. The fixtures do not make live federation calls.

## Verify and clean up

The two named allowed cases pass. The other cases fail with the field responsible for each decision. The new GitLab case must fail on `project_id`. Retain the expected and observed results. Delete the disposable copy.

Related reading: [GitHub Actions security](/github/), [GitLab CI runner isolation](/gitlab/) and [Google Cloud security](/gcp/).
