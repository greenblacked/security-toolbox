# Terraform GCP policy

The OPA / Conftest policy evaluates Terraform plan JSON for service-account keys, public Cloud Storage grants, bucket settings and internet-exposed SSH or RDP. It warns on buckets without CMEK.

It reads the **plan**, not the source, because the plan is what will be applied: variables are resolved, `for_each` is expanded, and a value built by a module is visible. A `count = 0` resource that never exists cannot be flagged, and a bucket created by a module cannot hide behind a variable.

## Run

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
```

Review plan data as sensitive. Unknown values and coverage limitations are described in the [policy coverage table](/policies/#public-gcs-coverage).

In CI, run it on the saved plan that will be applied, not on a fresh plan generated in a later job. A plan produced twice is two documents, and only one of them is what the apply will do.

## Rules

| Rule | Level | Why it is a finding | Fix |
| --- | --- | --- | --- |
| `google_service_account_key` | deny | A user-managed key is a long-lived credential that outlives every review and cannot be revoked by removing it from code | Delete the resource. Use Workload Identity Federation, an attached service account, or `--impersonate-service-account` |
| Storage IAM member or binding granting `allUsers` / `allAuthenticatedUsers` | deny | Every request on the internet can read or write the bucket | Remove the binding; publish through a load balancer or CDN with a dedicated bucket |
| Public ACL on a bucket or object (`predefined_acl`, `default_acl`, `role_entity`, `entity`) | deny | ACLs bypass the bucket IAM view that reviewers read | `predefined_acl = "private"`, delete `role_entity` entries, set `uniform_bucket_level_access = true` |
| `policy_data` grants a public member | deny | `google_storage_bucket_iam_policy` replaces the whole policy, so the grant is not visible in a per-member review | Build the policy from a literal or `data.google_iam_policy` in the same module, and remove the public member |
| `policy_data` unknown at plan time | warn | The value is not known when the plan is produced, so it cannot be checked | Use `jsonencode` on a literal, or a `data.google_iam_policy` in the same module, so the policy is resolved |
| `policy_data` is not a valid IAM policy object | warn | A malformed policy cannot be checked for public members | Fix the template; the plan will fail at apply if it stays malformed |
| Bucket without `public_access_prevention = "enforced"` | deny | The setting can be changed by anyone with bucket update rights after this plan | Set it, and enforce `storage.publicAccessPrevention` at the organisation |
| Bucket without `uniform_bucket_level_access = true` | deny | Object ACLs can reopen access that the bucket policy closed | Set it, and enforce `storage.uniformBucketLevelAccess` at the organisation |
| Bucket without a CMEK | warn | Data at rest is encrypted with Google-managed keys | `encryption { default_kms_key_name = google_kms_crypto_key.bucket.id }` where the data is regulated |
| Ingress from `0.0.0.0/0` or `::/0` to 22 or 3389 | deny | Administrative access from anywhere, including ranges you do not control | Allow IAP TCP forwarding (`35.235.240.0/20`) or a bastion subnet, and require OS Login |

The firewall rule is checked across every `allow` block, including port ranges, blocks with no ports, `protocol = "all"` and numeric protocols (`6`, `17`). A rule that allows every port is flagged the same way as one that names 22.

## A finding and its fix

```hcl
# Flagged: public bucket, no prevention, ACLs available
resource "google_storage_bucket" "assets" {
  name     = "acme-assets"
  location = "EU"
}

resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
```

```hcl
# Fixed: private bucket, ACLs off, public content served from its own bucket
resource "google_storage_bucket" "assets" {
  name                        = "acme-assets"
  location                    = "EU"
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  versioning { enabled = true }

  encryption { default_kms_key_name = google_kms_crypto_key.assets.id }
}
```

If the bucket genuinely serves public content, the fix is a second bucket behind the CDN, not a `#checkov:skip` and not a policy exemption. The policy is the thing that stops the next bucket from inheriting the exception.

## What the plan cannot resolve

- **Values unknown at plan time** — a computed attribute from another resource, or a provider function evaluated at apply. `policy_data` is warned about explicitly; other unknown attributes are not flagged.
- **What a module does internally** — the plan shows the rendered resources, which is the point, but the module's own conditions decide whether they exist.
- **State and drift** — a resource that exists but is missing from the plan is not in the policy's view.
- **IAM conditions** — a public grant with a condition is still a public grant; the policy flags it regardless.

## Exceptions

There is no ignore annotation in this policy, deliberately. A finding is either fixed, or the change does not go in, or the exemption is recorded somewhere a reviewer will see it — in the pull request, with an owner and a date, and with the organisation policy constraint that makes it unrepeatable. A skip comment in code outlives the person who wrote it and is invisible in the next plan.

## Pairing with Checkov

| Engine | Input | Catches | Misses |
| --- | --- | --- | --- |
| This policy | Plan JSON | Resolved values, rendered resources, `for_each` output | Anything not in the plan |
| [Checkov checks](/policies/checkov/) | HCL source | The same classes earlier, on the pull request that writes them | Values built by variables, modules or `file()` |

Run both. The HCL check fails faster, on the change that introduced the problem; the plan check fails on what will actually exist.

[All policies](/policies/) · [Terraform guide](/terraform/)
