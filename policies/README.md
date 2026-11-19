# Policies

Policy-as-code, report first. Every policy ships with unit tests and good/bad fixtures; `./policies/test.sh` runs them all (requires `opa` and `conftest`, `checkov` optional). It is not wired into CI yet; the intended CI step is `./policies/test.sh` with pinned opa, conftest and checkov.

| Path | Engine | Target | What it denies |
| --- | --- | --- | --- |
| `opa/terraform/gcp.rego` | OPA / Conftest | Terraform plan JSON | `google_service_account_key`; bucket IAM or ACLs granting `allUsers` / `allAuthenticatedUsers`, matched exactly so `group:allUsers@example.com` is not flagged (member, binding, `google_storage_bucket_iam_policy` via its parsed `policy_data` including on existing buckets not managed in the plan, and ACL `entity` / `role_entity` such as `READER:allUsers`; warns separately when `policy_data` is unknown at plan time or not a valid policy object); buckets without `public_access_prevention = "enforced"` or uniform bucket-level access; firewall ingress from `0.0.0.0/0` or `::/0` to 22/tcp or 3389/tcp+udp, across every allow block, including port ranges, blocks without ports, `protocol = "all"` and numeric protocols (`6`, `17`). Warns on buckets without CMEK. |
| `opa/kubernetes/pod_security.rego` | OPA / Conftest | Kubernetes manifests | privileged containers, hostPID / hostIPC / hostNetwork, hostPath volumes, missing `allowPrivilegeEscalation: false`, missing `runAsNonRoot: true`, `runAsUser: 0`, dangerous added capabilities. Warns on hostPort and missing memory limits. |
| `checkov/checks/` | Checkov | Terraform HCL | `CKV_STB_GCP_1` bucket public access prevention, `CKV_STB_GCP_2` SSH/RDP open to the internet (every allow block, port ranges, no-ports and `all`, numeric protocols), `CKV_STB_GCP_3` service-account keys, `CKV_STB_GCP_4` public GCS IAM, ACLs and predefined ACLs, matched exactly (see the coverage table), `CKV_STB_GCP_5` public members in `data.google_iam_policy`. |

## Public GCS coverage

Checked against the google provider docs (v8.12.0, Nov 2026) and the [GCS predefined ACL table](https://cloud.google.com/storage/docs/access-control/lists#predefined-acl). Public means exactly `allUsers` / `allAuthenticatedUsers` (for `role_entity`, the part after the first colon) or the predefined ACLs `publicRead`, `publicReadWrite`, `authenticatedRead`. `private`, `projectPrivate`, `bucketOwnerRead`, `bucketOwnerFullControl` and look-alikes such as `group:allUsers@example.com` pass. Each row has a positive and a negative fixture in both engines.

| Resource | Attribute | Rego (plan JSON) | Checkov (HCL) |
| --- | --- | --- | --- |
| `google_storage_bucket_iam_member` | `member` | yes | yes (`_4`) |
| `google_storage_bucket_iam_binding` | `members` | yes | yes (`_4`) |
| `google_storage_bucket_iam_policy` | `policy_data` | yes, parsed; warns if unknown or invalid | yes when resolvable (`jsonencode`, JSON string, same-module `data.google_iam_policy`), else UNKNOWN (`_4`) |
| `google_storage_managed_folder_iam_member` | `member` | yes | yes (`_4`) |
| `google_storage_managed_folder_iam_binding` | `members` | yes | yes (`_4`) |
| `google_storage_managed_folder_iam_policy` | `policy_data` | yes, as bucket policy | yes, as bucket policy (`_4`) |
| `data.google_iam_policy` | `binding.members` | n/a: plan JSON carries the rendered `policy_data` | yes (`_5`) |
| `google_storage_bucket_acl` | `predefined_acl` | yes | yes (`_4`) |
| `google_storage_bucket_acl` | `default_acl` (predefined default object ACL) | yes | yes (`_4`) |
| `google_storage_bucket_acl` | `role_entity` | yes | yes (`_4`) |
| `google_storage_object_acl` | `predefined_acl` | yes | yes (`_4`) |
| `google_storage_object_acl` | `role_entity` | yes | yes (`_4`) |
| `google_storage_default_object_acl` | `role_entity` | yes | yes (`_4`) |
| `google_storage_bucket_access_control` | `entity` | yes | yes (`_4`) |
| `google_storage_object_access_control` | `entity` | yes | yes (`_4`) |
| `google_storage_default_object_access_control` | `entity` | yes | yes (`_4`) |
| `google_storage_bucket` | `public_access_prevention` | yes (must be `enforced`) | yes (`_1`) |
| `google_storage_bucket` | `uniform_bucket_level_access` | yes (must be `true`) | no (use Checkov built-in `CKV_GCP_29`) |

Out of scope or not statically resolvable:

| Item | Why |
| --- | --- |
| `google_storage_bucket_object` ACLs | The resource has no ACL attribute in the current provider; object ACLs go through `google_storage_object_acl`, which is covered. |
| `google_storage_bucket.predefined_default_object_acl` | Not in the current provider; default object ACLs go through `default_acl`, `google_storage_default_object_acl` and `google_storage_default_object_access_control`, which are covered. |
| XML API spellings (`public-read`, ...) | The provider uses the JSON API, which takes the camelCase names; other spellings are not flagged. |
| IAM conditions on a public binding | The grant is flagged regardless of `condition`; conditions are not evaluated. |
| Project, folder or organisation IAM granting storage roles | Outside the bucket-level surface; enforce `iam.allowedPolicyMemberDomains` instead. |
| Signed URLs, HMAC keys | Credential-based access, not public grants. |
| Values unknown at plan time | Rego warns for `policy_data`; other unknown attributes are not flagged. |
| Checkov references it cannot render (variables, module outputs, `file()`) | `_4` returns UNKNOWN for `policy_data`; other attributes pass unless the literal is visible. Run the OPA policy on plan JSON for full resolution. |

## Usage

```bash
# Terraform plan JSON (what will actually be applied)
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json

# Terraform source with Checkov custom checks
checkov -d infra/ --external-checks-dir policies/checkov/checks

# Kubernetes manifests (rendered Helm/Kustomize output works too)
kustomize build overlays/prod | conftest test --policy policies/opa/kubernetes \
  --namespace kubernetes.pod_security -
```

The Kubernetes policy follows the Pod Security Standards baseline/restricted profiles and the Pod Security Standards section (5.2) of the CIS Kubernetes Benchmark. Item numbers inside 5.2 differ between benchmark versions, so messages name the control topic rather than a number. In-cluster, prefer Pod Security Admission (`pod-security.kubernetes.io/enforce: restricted`) and use this policy as the shift-left copy in CI.

Checkov resolves `policy_data` on `google_storage_bucket_iam_policy` when it is a `jsonencode(...)` literal, a JSON string, or a reference to a `data.google_iam_policy` in the same module. A variable, module output or `file()` result cannot be resolved statically: `CKV_STB_GCP_4` reports those as UNKNOWN (not passed), `CKV_STB_GCP_5` still checks the data source where it is declared, and the OPA policy on plan JSON sees the rendered value.

The plan fixtures are hand-written, trimmed `terraform show -json` documents containing only the fields the policies read.

Planned: `custodian/` (Cloud Custodian for running GCP resources) and `kyverno/`.
