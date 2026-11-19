# GCP

Baseline for production Google Cloud projects. Report first: every item below can be checked read-only before anything is changed.

## Identity and access

- **No user-managed service-account keys.** Enforce the organisation policy constraint `iam.disableServiceAccountKeyCreation` (and `iam.disableServiceAccountKeyUpload`). Use attached service accounts on Compute/GKE/Cloud Run, Workload Identity Federation for GKE, and Workload Identity Federation for CI (GitHub OIDC). The Terraform policy in [`policies/opa/terraform`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/terraform/gcp.rego) denies `google_service_account_key`.
- **No basic roles in production.** `roles/owner`, `roles/editor` and `roles/viewer` grant thousands of permissions. Replace with predefined or custom roles; use IAM Recommender to find unused permissions.
- **Grant to groups, not users.** Bind roles to Google Groups so access reviews and offboarding happen in one place.
- **Default compute service account.** Do not let workloads run as `PROJECT_NUMBER-compute@developer.gserviceaccount.com`; enforce `iam.automaticIamGrantsForDefaultServiceAccounts` so it is not granted Editor.
- **Domain restricted sharing.** `iam.allowedPolicyMemberDomains` stops grants to `allUsers`, `allAuthenticatedUsers` and outside domains.
- Review grants against last-used evidence with the `access-review` skill.

```bash
# Who holds basic roles on a project
gcloud projects get-iam-policy PROJECT --flatten=bindings[].members \
  --filter='bindings.role:(roles/owner roles/editor)' --format='table(bindings.role,bindings.members)'
# User-managed keys that exist today
gcloud iam service-accounts list --format='value(email)' | while read -r sa; do
  gcloud iam service-accounts keys list --iam-account "$sa" --managed-by=user --format='value(name)' | sed "s|^|$sa |"
done
```

## Storage

- `storage.publicAccessPrevention` and `storage.uniformBucketLevelAccess` organisation policies on; buckets set `public_access_prevention = "enforced"`.
- Public content goes behind a load balancer or CDN with a dedicated bucket, not by granting `allUsers` on a data bucket.
- CMEK (Cloud KMS) for regulated data; retention policies and object versioning where deletion would hurt.

## Network

- No `0.0.0.0/0` ingress to SSH (22) or RDP (3389). Use IAP TCP forwarding (source range `35.235.240.0/20`) or a bastion.
- `compute.vmExternalIpAccess` restricts which VMs may have public IPs; Cloud NAT for egress.
- Private Google Access on subnets; VPC Service Controls perimeters around projects holding sensitive data.
- VPC flow logs and firewall rule logging on production VPCs.
- Firewall rule order: the lowest priority number wins, and at equal priority a deny beats an allow. Hierarchical firewall policies are evaluated before VPC firewall rules, and network firewall policies before or after them depending on the network's enforcement order, so review the effective rules (`gcloud compute instances network-interfaces get-effective-firewalls`). Rule changes apply to new connections only.

## Logging and detection

- Cloud Audit Logs: Admin Activity is always on; Data Access logs are off by default for every service except BigQuery, so enable them for IAM, KMS, Secret Manager and Storage in production.
- Retention: the `_Required` bucket keeps Admin Activity and System Event logs for 400 days; the `_Default` bucket keeps everything else, including Data Access logs, for 30 days unless you raise it. Retention is set on each project's `_Default` bucket; organisation and folder default resource settings control the location, CMEK and `_Default` sink of new buckets, not their retention. Raising it is not retroactive.
- Organisation-level aggregated sink to a locked log bucket or a separate logging project, with retention matching your incident-response needs. Set the retention and lock before an incident; locking a log bucket is irreversible.
- Security Command Center for misconfiguration findings; alert on IAM policy changes, key creation and firewall changes. See the `detection-engineering` skill for rule hygiene.

## Organisation policies worth enforcing

| Constraint | Effect |
| --- | --- |
| `iam.disableServiceAccountKeyCreation` | No new service-account keys |
| `iam.allowedPolicyMemberDomains` | Only your identities in IAM policies |
| `storage.publicAccessPrevention` | Buckets cannot be made public |
| `storage.uniformBucketLevelAccess` | No object ACLs |
| `compute.vmExternalIpAccess` | Allow-list for VMs with public IPs |
| `compute.requireOsLogin` | SSH through IAM, not metadata keys |
| `compute.requireShieldedVm` | Shielded VM for new instances |
| `sql.restrictPublicIp` | Cloud SQL without public IP |

Roll constraints out in dry-run mode first (organisation policy dry-run or a test folder) and check violations before enforcing.

Planned: Cloud Custodian policies for running resources under `policies/custodian/`.
