# Policies

Policy-as-code, report first. Every policy ships with unit tests and good/bad fixtures; `./policies/test.sh` runs them all (requires `opa` and `conftest`, `checkov` optional). It is not wired into CI yet; the intended CI step is `./policies/test.sh` with pinned opa, conftest and checkov.

| Path | Engine | Target | What it denies |
| --- | --- | --- | --- |
| `opa/terraform/gcp.rego` | OPA / Conftest | Terraform plan JSON | `google_service_account_key`; bucket IAM granting `allUsers` / `allAuthenticatedUsers`; buckets without `public_access_prevention = "enforced"` or uniform bucket-level access; firewall ingress from `0.0.0.0/0` or `::/0` to 22/tcp or 3389/tcp+udp, across every allow block, including port ranges, blocks without ports, `protocol = "all"` and numeric protocols (`6`, `17`). Warns on buckets without CMEK. |
| `opa/kubernetes/pod_security.rego` | OPA / Conftest | Kubernetes manifests | privileged containers, hostPID / hostIPC / hostNetwork, hostPath volumes, missing `allowPrivilegeEscalation: false`, missing `runAsNonRoot: true`, `runAsUser: 0`, dangerous added capabilities. Warns on hostPort and missing memory limits. |
| `checkov/checks/` | Checkov | Terraform HCL | `CKV_STB_GCP_1` bucket public access prevention, `CKV_STB_GCP_2` SSH/RDP open to the internet (every allow block, port ranges, no-ports and `all`, numeric protocols), `CKV_STB_GCP_3` service-account keys, `CKV_STB_GCP_4` public bucket IAM members. |

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

The plan fixtures are hand-written, trimmed `terraform show -json` documents containing only the fields the policies read.

Planned: `custodian/` (Cloud Custodian for running GCP resources) and `kyverno/`.
