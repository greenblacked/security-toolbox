# Terraform policy gate

Use local plan fixtures to practice interpreting a GCP policy gate. Allow 45 minutes. Install Conftest.

## Exercise

Run Conftest from the [extracted lab kit directory](/labs/#get-the-lab-kit). The Terraform plan fixtures are synthetic. This exercise needs neither Terraform nor Google Cloud credentials.

```bash
(
  set -eu
  policy_dir=policies/opa/terraform
  conftest test -p "$policy_dir" -n terraform.gcp "$policy_dir/fixtures/plan-good.json"
  status=0
  conftest test -p "$policy_dir" -n terraform.gcp "$policy_dir/fixtures/plan-bad.json" || status=$?
  test "$status" -eq 1
)
```

## Verify and clean up

The good plan passes. The bad plan blocks the gate and includes the affected resource address in its failure output. Capture one finding and its resource address, then explain how to verify a proposed remediation against the same policy. The exercise writes no files. Discard any optional working copy or diagnostic export when finished.

Related reading: [Terraform plan review](/terraform/) and [Terraform GCP policy](/policies/terraform/).
