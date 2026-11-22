# Checkov GCP checks

The custom Terraform HCL checks cover public access prevention, internet-exposed SSH/RDP, service-account keys and public Cloud Storage IAM or ACL grants. Some references cannot be resolved statically and are reported as unknown.

They read HCL source, so they fail on the pull request that writes the problem, before a plan exists. The trade is that a value built by a variable or a module output is not visible to them.

## Run

```bash
checkov -d infra/ --external-checks-dir policies/checkov/checks
```

Add `--compact --quiet` for a one-line-per-finding summary, and `-o sarif --output-file-path results` where a code-scanning upload is available. The custom checks live beside the built-in GCP ones; run them together rather than replacing the built-in set.

## The five checks

| ID | Resource | Fails when | Why |
| --- | --- | --- | --- |
| `CKV_STB_GCP_1` | `google_storage_bucket` | `public_access_prevention` is not `"enforced"` | The bucket can be made public later by anyone with update rights; the setting is what stops it |
| `CKV_STB_GCP_2` | `google_compute_firewall` | An `allow` block admits `0.0.0.0/0` or `::/0` to 22/tcp or 3389/tcp+udp | Administrative access from the whole internet; use IAP TCP forwarding (`35.235.240.0/20`) or a bastion |
| `CKV_STB_GCP_3` | `google_service_account_key` | Any user-managed key exists | A long-lived credential that survives every review; use Workload Identity Federation |
| `CKV_STB_GCP_4` | Bucket and object IAM/ACL resources | A member is exactly `allUsers` or `allAuthenticatedUsers`, or a predefined ACL is `publicRead`, `publicReadWrite` or `authenticatedRead` | Public data access, whether granted by IAM, an ACL or `policy_data` |
| `CKV_STB_GCP_5` | `data.google_iam_policy` | A binding's members include a public member | The public grant is built in a data source and rendered into `policy_data` later |

`CKV_STB_GCP_2` is checked across every `allow` block, including port ranges, blocks with no ports, `protocol = "all"` and numeric protocols (`6`, `17`). `CKV_STB_GCP_4` matches exactly, so `group:allUsers@example.com` passes — the look-alike is not a public grant.

## What resolves and what does not

`policy_data` on `google_storage_bucket_iam_policy` is checked when Checkov can resolve it:

| Form | Resolved |
| --- | --- |
| `jsonencode({...})` with a literal | yes |
| A JSON string literal | yes |
| A reference to `data.google_iam_policy` in the same module | yes (`_5` checks the data source) |
| A variable, module output, or `file()` | no — reported as `UNKNOWN`, not as passed |
| A `templatefile()` with a computed path | no |

`UNKNOWN` is deliberately not a pass. A result that cannot be resolved is the case where the reviewer has to read the code, and the [Terraform plan policy](/policies/terraform/) resolves it because the plan carries the rendered value.

## Skips

A skip is a decision with a reason attached, in the line above the resource:

```hcl
#checkov:skip=CKV_STB_GCP_4:CDN origin bucket, public by design, see SEC-412
resource "google_storage_bucket_iam_binding" "cdn" {
  # ...
}
```

Rules for a skip that will survive a review: it names the ticket, it says why the finding is wrong here rather than why it is inconvenient, and it is removed when the reason stops being true. A skip with no reason is a finding that the next reviewer cannot evaluate.

## Relationship to the OPA policy

| Engine | Input | Runs | Strength |
| --- | --- | --- | --- |
| Checkov checks | HCL source | On the pull request | Fails earliest; catches the change that introduces it |
| [Terraform plan policy](/policies/terraform/) | Plan JSON | On the saved plan | Resolves variables, modules and `for_each`; sees what will exist |

Neither is a superset. Run both, and treat a finding from either as blocking until it is fixed or has a recorded exception.

Compare engine coverage and limitations in the [public GCS coverage table](/policies/#public-gcs-coverage). For resolved values, also evaluate the [Terraform plan policy](/policies/terraform/).

[All policies](/policies/) · [Terraform guide](/terraform/)
