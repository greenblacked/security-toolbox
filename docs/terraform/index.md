# Terraform / IaC

## Review the plan, not the diff

The plan JSON is what will be applied. Produce it in a trusted pipeline and run policy against it:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
```

The [`iac-review`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/iac-review/SKILL.md) skill covers blast radius, replacements, drift, state moves and the verdict.

## Policies in this repository

| Policy | Engine | Denies |
| --- | --- | --- |
| [`opa/terraform/gcp.rego`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/terraform/gcp.rego) | OPA / Conftest on plan JSON | `google_service_account_key`; public GCS access through IAM, ACLs and predefined ACLs (see the [coverage table](https://github.com/greenblacked/security-toolbox/blob/main/policies/README.md#public-gcs-coverage)); buckets without enforced public access prevention or uniform access; SSH/RDP open to the internet. Warns on buckets without CMEK |
| [`checkov/checks/`](https://github.com/greenblacked/security-toolbox/blob/main/policies/checkov/checks) | Checkov on HCL | `CKV_STB_GCP_1` bucket public access prevention, `CKV_STB_GCP_2` SSH/RDP open to the internet, `CKV_STB_GCP_3` service-account keys, `CKV_STB_GCP_4` public GCS IAM, ACLs and predefined ACLs, `CKV_STB_GCP_5` public members in `data.google_iam_policy`. Uniform access is left to the built-in `CKV_GCP_29`; see the [coverage table](https://github.com/greenblacked/security-toolbox/blob/main/policies/README.md#public-gcs-coverage) |

Run them with `./policies/test.sh` (unit tests plus good/bad fixtures) and against your own code:

```bash
checkov -d infra/ --external-checks-dir policies/checkov/checks
```

## Secure patterns

- **Pin everything.** `required_version` and `required_providers` with version constraints, a committed `.terraform.lock.hcl`, modules pinned to a tag or commit SHA.
- **State is a secret.** Remote state in a GCS bucket with uniform access, public access prevention, versioning and CMEK; only the pipeline service account can write it. `sensitive = true` hides values from output, not from state.
- **No secrets in variables files.** Read them at apply time from Secret Manager (`google_secret_manager_secret_version` data source) or pass references, not values.
- **Least-privilege pipeline identity.** Plan with a read-only service account on PRs; apply with a separate account through Workload Identity Federation, never a downloaded key.
- **Additive IAM.** Prefer `google_*_iam_member` over `_iam_binding` / `_iam_policy`, which replace bindings authoritatively and can remove access managed elsewhere.
- **Guard stateful resources.** `deletion_protection` on databases and clusters, `lifecycle { prevent_destroy = true }` on irreplaceable data.

## Recommended scanners

- [Checkov](https://www.checkov.io/) and [Trivy](https://trivy.dev/) (`trivy config`, which absorbed tfsec) for broad built-in rules.
- Conftest / OPA for organisation-specific rules against plan JSON.
- Gate on new findings; record exceptions with an owner and expiry in code (`#checkov:skip=ID:reason`), not in a wiki.
