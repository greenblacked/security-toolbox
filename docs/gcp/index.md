# GCP

**Who this is for:** cloud platform engineers responsible for a Google Cloud organisation. You should be able to read an IAM policy and run `gcloud` against a project.

Baseline for production Google Cloud projects. Report first: every item below can be checked read-only before anything is changed.

## Organisation structure

Most GCP security failures are organisational, not per-project. Three decisions set the ceiling on everything else.

- **One organisation, folders per environment and per business unit.** Policies and IAM granted at a folder apply to every project under it, which is the only place a guardrail cannot be forgotten by a new project.
- **A separate project for logging and one for the security tooling.** Audit logs written to the project they describe can be deleted by whoever compromises that project.
- **A break-glass folder with the only `roles/owner` grants**, its members in a group that pages when used.

Nothing sensitive should be reachable by a project created from the console in five minutes. A project that is insecure by default is the vulnerability, because most projects are created that way.

### The baseline is already enforced

Organisations created on or after 3 May 2024 arrive with seven constraints already enforced, under the **managed** names: `iam.managed.disableServiceAccountKeyCreation`, `iam.managed.disableServiceAccountKeyUpload`, `iam.automaticIamGrantsForDefaultServiceAccounts`, `iam.allowedPolicyMemberDomains`, `essentialcontacts.managed.allowedContactDomains`, `compute.managed.restrictProtocolForwardingCreationForTypes` and `storage.uniformBucketLevelAccess`.

That changes what the work is. On a new organisation the task is not to add these but to find out what is already inherited, because domain-restricted sharing blocks a project that legitimately needs an outside identity, and a blocked key creation surfaces as a confusing API error rather than a policy denial.

```bash
gcloud resource-manager org-policies list --organization=ORG_ID
```

There is a second and larger consequence. A growing set of constraints is **automatically enforced** by Google with a restrictive default even where nobody wrote a policy — the `iam.managed.*`, `container.managed.*` and `compute.managed.*` families. For those, the assumption that "no policy means allowed" is wrong, and an audit that reads only the policies you wrote will miss them. Read the *effective* policy rather than the configured one.

The managed families are also the ones that support **dry-run and Policy Simulator**, which makes them the only way to test an enforcement change before it breaks a workload. The legacy names (`iam.disableServiceAccountKeyCreation`) do not.

## Identity and access

- **No user-managed service-account keys.** Enforce the organisation policy constraint `iam.disableServiceAccountKeyCreation` (and `iam.disableServiceAccountKeyUpload`). Use attached service accounts on Compute/GKE/Cloud Run, Workload Identity Federation for GKE, and Workload Identity Federation for CI (GitHub OIDC). The Terraform policy in [`policies/opa/terraform`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/terraform/gcp.rego) denies `google_service_account_key`.
- **No basic roles in production.** `roles/owner`, `roles/editor` and `roles/viewer` grant thousands of permissions. Replace with predefined or custom roles; use IAM Recommender to find unused permissions.
- **Grant to groups, not users.** Bind roles to Google Groups so access reviews and offboarding happen in one place.
- **Default compute service account.** Do not let workloads run as `PROJECT_NUMBER-compute@developer.gserviceaccount.com`; enforce `iam.automaticIamGrantsForDefaultServiceAccounts` so it is not granted Editor.
- **Domain restricted sharing.** `iam.allowedPolicyMemberDomains` stops grants to `allUsers`, `allAuthenticatedUsers` and outside domains.
- Review grants against last-used evidence with the [`access-review`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/access-review/SKILL.md) skill.
- Report the grants before changing them: [`checks/gcp/iam-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gcp/iam-report.sh) reads a project IAM policy and fails on public members, standing basic roles and the default compute account holding Editor.

```bash
# Who holds basic roles on a project
gcloud projects get-iam-policy PROJECT --flatten=bindings[].members \
  --filter='bindings.role:(roles/owner roles/editor)' --format='table(bindings.role,bindings.members)'
# User-managed keys that exist today
gcloud iam service-accounts list --format='value(email)' | while read -r sa; do
  gcloud iam service-accounts keys list --iam-account "$sa" --managed-by=user --format='value(name)' | sed "s|^|$sa |"
done
# Any public or cross-domain binding anywhere in the organisation
gcloud asset search-all-iam-policies --scope=organizations/ORG_ID \
  --query='policy:allUsers OR policy:allAuthenticatedUsers'
```

### Conditions instead of more roles

An IAM condition narrows a grant to a time window, a resource name, or a request attribute. It is how you grant a permission that is only safe sometimes, rather than inventing a custom role for it.

- Time-bound elevation: `request.time < timestamp("2026-12-01T00:00:00Z")` for a contractor's access, expiring without anyone remembering to remove it.
- Resource-name scoping: a role granted only on `projects/_/buckets/prefix-*` rather than the whole project.
- Tag-based: grant on resources with `env=prod` only, so a copy in a sandbox project does not inherit it.

A condition that nobody can read is a permanent grant with extra steps. Write the reason in the binding's description and review conditions on the same cadence as the grants.

### Deny policies

Allow policies accumulate; deny policies subtract. A deny policy names principals and permissions and is evaluated before any allow, which makes it the tool for "never, by anyone" rather than "not by this group". Use it for the operations you would page on: disabling audit logs, deleting a log bucket, creating a service-account key, changing an organisation policy. Deny is not a substitute for least privilege — it is the backstop when a grant is wrong.

### Impersonation instead of keys

Where a key exists today because "the tool needs credentials", the replacement is usually impersonation:

```bash
# Short-lived credentials from a principal that is allowed to impersonate
gcloud storage ls --impersonate-service-account=SA@PROJECT.iam.gserviceaccount.com
gcloud auth print-access-token --impersonate-service-account=SA@PROJECT.iam.gserviceaccount.com
```

The caller needs `roles/iam.serviceAccountTokenCreator` on the service account, which is auditable, revocable and does not leave a credential on disk. Anything that prints an access token must not also log it: the token is a bearer credential for its lifetime.

## Service accounts in practice

- One service account per workload, named for the workload. A shared account makes the audit log useless and the permission set the union of every consumer.
- `roles/iam.serviceAccountUser` lets a principal *attach* an account to a resource; `roles/iam.serviceAccountTokenCreator` lets it *act as* the account. The second is far stronger and is usually the one granted by mistake.
- Delete unused accounts. An account with no key and no binding is still a principal that a future grant can attach to.
- `gcloud iam service-accounts list --format='value(email)'` and last-authentication data tell you which are dormant; disabling is reversible, deleting is not.

## Compute

- `compute.requireOsLogin` — SSH through IAM and the audit log, not project-wide metadata keys.
- `compute.requireShieldedVm` — vTPM and integrity monitoring for new instances.
- `compute.disableSerialPortAccess` and `compute.disableSerialPortLogging` — the serial console bypasses the guest's own access controls.
- `compute.disableNestedVirtualization` — a nested hypervisor inside a VM defeats most host-level assumptions.
- `compute.vmCanIpForward` and `compute.vmExternalIpAccess` — restrict who can route traffic and who can hold a public address.
- Guest attributes and the metadata server: the metadata server is reachable at `169.254.169.254` from any workload that can make an HTTP request. Workload Identity removes the node credential from it; do not put secrets in instance metadata.
- Patch through the OS Config / VM Manager path you can report on, not by hand.

## Storage and data

- `storage.publicAccessPrevention` and `storage.uniformBucketLevelAccess` organisation policies on; buckets set `public_access_prevention = "enforced"`.
- Public content goes behind a load balancer or CDN with a dedicated bucket, not by granting `allUsers` on a data bucket.
- CMEK (Cloud KMS) for regulated data; retention policies and object versioning where deletion would hurt.
- Bucket IAM is the control surface; ACLs are the thing you disable. `uniformBucketLevelAccess` makes that structural rather than a habit.
- Signed URLs are bearer credentials: bound them to the shortest lifetime the client tolerates, and treat a logged URL as a leaked credential.
- BigQuery: grant dataset-level access, prefer authorised views over broad table access, and remember that `roles/bigquery.dataViewer` on a dataset is every table in it. Row-level and column-level policies are the tools for partial access.

## Network

- No `0.0.0.0/0` ingress to SSH (22) or RDP (3389). Use IAP TCP forwarding (source range `35.235.240.0/20`) or a bastion.
- `compute.vmExternalIpAccess` restricts which VMs may have public IPs; Cloud NAT for egress.
- Private Google Access on subnets; VPC Service Controls perimeters around projects holding sensitive data.
- VPC flow logs and firewall rule logging on production VPCs.
- Firewall rule order: the lowest priority number wins, and at equal priority a deny beats an allow. Hierarchical firewall policies are evaluated before VPC firewall rules, and network firewall policies before or after them depending on the network's enforcement order. Rule changes apply to new connections only, so an old session can outlive the rule that closed it.
- VPC Service Controls are the control that stops data leaving a perimeter even when an identity has permission. A perimeter without a dry-run period first will break a workload you did not know crossed the boundary; run in dry-run, read the violations, then enforce.

## Logging and detection

- Cloud Audit Logs: Admin Activity is always on; Data Access logs are off by default for every service except BigQuery, so enable them for IAM, KMS, Secret Manager and Storage in production.
- Retention: the `_Required` bucket keeps Admin Activity and System Event logs for 400 days; the `_Default` bucket keeps everything else, including Data Access logs, for 30 days unless you raise it. Retention is set on each project's `_Default` bucket; organisation and folder default resource settings control the location, CMEK and `_Default` sink of new buckets, not their retention. Raising it is not retroactive.
- Organisation-level aggregated sink to a locked log bucket or a separate logging project, with retention matching your incident-response needs. Set the retention and lock before an incident; locking a log bucket is irreversible.
- Security Command Center for misconfiguration findings; alert on IAM policy changes, key creation and firewall changes. See the [`detection-engineering`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/detection-engineering/SKILL.md) skill for rule hygiene.

The events worth paging on, because each one is either an incident or a mistake:

| Event | Why it pages |
| --- | --- |
| `SetIamPolicy` on an organisation, folder or production project | Privilege escalation in one call |
| `google.iam.admin.v1.CreateServiceAccountKey` | A key that outlives every review |
| A log sink, log bucket or exclusion deleted or changed | The attacker removing the evidence |
| An organisation policy constraint disabled or loosened | The guardrail being taken off |
| A bucket's `publicAccessPrevention` set to `inherited` | The data being exposed |
| A firewall rule opened to `0.0.0.0/0` on 22 or 3389 | Remote access from anywhere |
| `SecretAccessor` granted at project scope | Every secret in the project |

```bash
# Recent IAM changes, from the audit log
gcloud logging read 'protoPayload.methodName="SetIamPolicy"' --limit=20 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,resource.type,resource.labels.project_id)'
# Log sinks that are not in the logging project
gcloud logging sinks list --project=PROJECT --format='table(name,destination)'
```

## Organisation policies worth enforcing

| Constraint | Effect |
| --- | --- |
| `iam.disableServiceAccountKeyCreation` | No new service-account keys |
| `iam.disableServiceAccountKeyUpload` | No imported public keys either |
| `iam.allowedPolicyMemberDomains` | Only your identities in IAM policies |
| `iam.automaticIamGrantsForDefaultServiceAccounts` | Default compute account does not get Editor |
| `storage.publicAccessPrevention` | Buckets cannot be made public |
| `storage.uniformBucketLevelAccess` | No object ACLs |
| `compute.vmExternalIpAccess` | Allow-list for VMs with public IPs |
| `compute.requireOsLogin` | SSH through IAM, not metadata keys |
| `compute.requireShieldedVm` | Shielded VM for new instances |
| `compute.disableSerialPortAccess` | No serial console |
| `compute.disableNestedVirtualization` | No hypervisor inside a VM |
| `compute.skipDefaultNetworkCreation` | No permissive `default` VPC |
| `sql.restrictPublicIp` | Cloud SQL without public IP |
| `run.allowedIngress` | Cloud Run services not publicly invokable |
| `gcp.resourceLocations` | Data residency for resources |

Roll constraints out in dry-run mode first (organisation policy dry-run or a test folder) and check violations before enforcing.

```yaml
# policy.yaml — a boolean constraint
constraint: constraints/iam.disableServiceAccountKeyCreation
booleanPolicy:
  enforced: true
```

```bash
gcloud resource-manager org-policies set-policy policy.yaml --organization=ORG_ID
gcloud resource-manager org-policies describe constraints/iam.disableServiceAccountKeyCreation \
  --organization=ORG_ID --effective
```

## Serverless

- **Cloud Run:** `--ingress=internal` unless the service is genuinely public, `--no-allow-unauthenticated` for service-to-service, and `--set-secrets` rather than environment values baked into a revision. A revision is immutable, which means a leaked value in one stays leaked until the revision is replaced.
- **Cloud Functions:** the runtime service account is the security boundary. Give it its own account with the permissions of that function only; the default account is the whole project's.
- **Pub/Sub and Eventarc** push subscriptions need authentication; an unauthenticated push endpoint is an open invocation.

## Next

- [Terraform](https://github.com/greenblacked/security-toolbox/blob/main/docs/terraform/index.md) — reviewing the plan that will create these resources.
- [Checks](https://github.com/greenblacked/security-toolbox/blob/main/checks/README.md) — the GKE report and workload checks.
- [Policies](https://github.com/greenblacked/security-toolbox/blob/main/policies/README.md) — the Conftest and Checkov rules that deny public buckets, open admin ports and service-account keys.

Planned: Cloud Custodian policies for running resources under `policies/custodian/`.
