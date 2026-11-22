# Terraform / IaC

**Who this is for:** engineers who review or apply Terraform against production. You should know what a plan contains and how remote state works.

## Review the plan, not the diff

The plan JSON is what will be applied. Produce it in a trusted pipeline and run policy against it:

```bash
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test --policy policies/opa/terraform --namespace terraform.gcp plan.json
```

The [`iac-review`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/iac-review/SKILL.md) skill covers blast radius, replacements, drift, state moves and the verdict.

A source diff tells you what someone typed. A plan tells you what will happen: which resources are created, which are replaced, and which are destroyed. Those are different documents, and only the second one is the change.

## Reading a plan properly

```bash
# Every action, one line per resource
jq -r '.resource_changes[] | "\(.change.actions|join("+"))  \(.address)"' plan.json

# What will be destroyed — read this list before anything else
jq -r '.resource_changes[] | select(.change.actions | index("delete")) | .address' plan.json

# Replacements, which show as delete+create and are the expensive surprise
jq -r '.resource_changes[] | select((.change.actions|index("delete")) and (.change.actions|index("create"))) | .address' plan.json
```

`terraform plan -detailed-exitcode` returns `0` for no changes, `1` for an error and `2` for a non-empty plan. That makes "does this plan do anything" a check a pipeline can run instead of a human reading the output.

Order of reading:

1. **Destroys and replacements first.** A replacement of a database, a bucket or a cluster is an outage with a data question attached, and it is the finding that matters. `lifecycle { prevent_destroy = true }` and provider `deletion_protection` turn the mistake into a plan failure.
2. **Then the blast radius**: how many resources, in which projects, and whether any are outside the module that was meant to change.
3. **Then the security delta**: new IAM bindings, new public access, new open firewall rules, a key that appeared.
4. **Then the diff itself**, to see whether the shape matches the intent.

A plan that touches resources outside the directory under review is a finding on its own: either the state is shared more widely than the reviewers think, or the change is not scoped to what was described.

### What the plan cannot tell you

- **Whether production has drifted.** `plan` refreshes state, but a plan reviewed against a stale state describes a different world. Run a scheduled plan against production and alert on `-detailed-exitcode = 2` when nothing was merged.
- **What the provider will do inside a resource.** An in-place update of an IAM policy is one line in the plan and a permission change for every principal in it.
- **Whether the value is a secret.** A plan prints `(sensitive value)` and still writes the plaintext to the state file and to CI logs if you are careless with `-json`.
- **Whether the apply will succeed.** Depends on quota, API enablement and ordering that the plan does not model.

## State is the crown jewel

The state file contains every attribute of every managed resource, including generated passwords, keys and connection strings. Treat it as a production secret with a longer life than most.

- **Remote, encrypted, access-controlled backend.** A GCS bucket with uniform access, public access prevention, versioning and CMEK, reachable only by the pipeline identity and a named break-glass group.
- **Versioning and object retention.** A corrupted or truncated state is recoverable only if a previous version exists.
- **Locking.** GCS and most managed backends lock automatically; a local or shared-filesystem backend does not. Two concurrent applies to one state produce resources nobody owns.
- **One state per blast radius.** A single state for an entire organisation means every plan is a plan of everything, and a mistake in one team's module can destroy another's.
- **No state in a repository.** Not even encrypted, and not "temporarily" to move a resource.

```bash
# Who has read access to the state bucket
gcloud storage buckets get-iam-policy gs://STATE_BUCKET --format=json
# A state object is a plaintext document
gcloud storage ls --recursive gs://STATE_BUCKET
```

`sensitive = true` hides a value from CLI output. It does not encrypt it, remove it from state, or stop `terraform show` from printing it.

Terraform 1.10 and later offer two ways to keep a value out of state entirely:

- **Ephemeral resources** (`ephemeral "..."`) exist for the length of an operation and are never written to state or to plan files.
- **Write-only arguments** (`password_wo`, `secret_string_wo`) accept a value that reaches the provider and is then discarded. Updating one requires bumping a companion `*_wo_version` integer, which turns a rotation into a visible line in the plan instead of an invisible change in a secret store.

Encrypting and locking the backend is still necessary for everything else in state. It is no longer the only answer for a secret the configuration has to pass through.

## Apply pipeline

The pipeline, not the engineer, is the only thing allowed to apply.

1. **Plan on pull request** with a read-only identity. The plan is posted as a comment or an artifact so the reviewer reads the same bytes that will be applied.
2. **Bind the approval to that plan.** Re-running plan after approval invalidates the approval: a saved plan file is the unit of review, and applying a freshly re-planned change applies something nobody read.
3. **Apply on merge** with a write identity reached through OIDC, never a downloaded key.
4. **Serialize applies** per state with a concurrency group, so two merges cannot interleave.
5. **No local apply.** A laptop has no audit trail, no approval and usually a different provider version.

```bash
terraform init -input=false
terraform validate
terraform plan -input=false -lock-timeout=5m -out=tfplan
terraform apply -input=false tfplan   # the reviewed file, not a fresh plan
```

- `TF_IN_AUTOMATION=1` keeps output free of interactive advice and makes CI logs readable.
- `-lock-timeout` turns a concurrent apply into a wait instead of an immediate failure that someone reruns blindly.
- Credentials reach the pipeline through OIDC; see [`workload identity`](https://github.com/greenblacked/security-toolbox/blob/main/docs/github/index.md).

## Pinning

- `required_version` and `required_providers` with constraints, and `.terraform.lock.hcl` committed. The lock file is what makes the provider version the same on every machine and in CI.
- `~> 6.1` allows `6.x` but not `7.0`. A constraint of `>= 6.0` allows the major version that changes behaviour, which is the one you did not test.
- Lock the provider for every platform the team and CI use: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`. Otherwise a Mac applies with a provider build CI never saw.
- Modules pinned to a tag or a commit SHA, never to a branch. A module on `main` is a supply-chain dependency that updates itself.
- `terraform init -upgrade` is a reviewed change: it rewrites the lock file, and the diff is the review.

## Refactoring without recreation

Moving a resource in the configuration without moving it in state destroys and recreates it. Three blocks exist so that a rename is a rename:

```hcl
# Rename or move between modules without touching the resource
moved {
  from = google_storage_bucket.logs
  to   = module.logging.google_storage_bucket.this
}

# Adopt a resource that already exists
import {
  to = google_storage_bucket.existing
  id = "existing-bucket-name"
}

# Drop it from state but leave it running
removed {
  from = google_storage_bucket.legacy
  lifecycle { destroy = false }
}
```

- `moved` is free and reviewable; `terraform state mv` does the same thing with no record in the configuration.
- An `import` block plus a plan is safer than `terraform import`, because the plan shows what will change to make the configuration match.
- A `removed` block with `destroy = false` is how you stop managing something without deleting it. The alternative — deleting the resource block — is a destroy.

## Common GCP Terraform traps

| Pattern | What happens | Use instead |
| --- | --- | --- |
| `google_project_iam_policy` | Replaces every binding on the project with the ones in the file | `google_project_iam_member` per grant |
| `google_project_iam_binding` | Authoritative for that role; removes members added elsewhere | `_member` |
| `google_storage_bucket_iam_binding` with `allUsers` | The bucket is public; the plan shows one line | The policy in this repository denies it |
| `count` for a list of resources | Removing an item from the middle re-indexes and recreates the rest | `for_each` on a map keyed by name |
| A `google_project_service` with `disable_on_destroy` | Destroying the module can disable an API another project depends on | Explicit `disable_on_destroy = false` |
| Default network left in place | `0.0.0.0/0` on several ports from the moment the project exists | `compute.skipDefaultNetworkCreation` |
| `google_container_cluster` without `deletion_protection` | A mistyped address in a destroy deletes the cluster | `deletion_protection = true` |
| `google_sql_database_instance` in a `for_each` | Removing a key destroys a database | `prevent_destroy` on the database |

## Testing

Three layers, cheapest first:

- `terraform fmt -check -recursive` and `terraform validate` — syntax and reference errors before a plan costs anything.
- `terraform test` — native tests with plan assertions and provider mocks, so a module's defaults and optional branches are checked without creating real resources.
- Policy on the plan — [`policies/opa/terraform`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/terraform/gcp.rego) for the rules this repository ships, Checkov for the broad built-in set.

A policy that only runs on apply is a report, not a gate. Run it on the plan in the pull request, and treat a new finding as blocking unless it has a written exception with an owner and an expiry.

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
- **Small states.** One state per service or environment, so a plan is reviewable and a mistake is bounded.

## Recommended scanners

- [Checkov](https://www.checkov.io/) and [Trivy](https://trivy.dev/) (`trivy config`, which absorbed tfsec) for broad built-in rules.
- Conftest / OPA for organisation-specific rules against plan JSON.
- Gate on new findings; record exceptions with an owner and expiry in code (`#checkov:skip=ID:reason`), not in a wiki.

## Next

- [GCP](https://github.com/greenblacked/security-toolbox/blob/main/docs/gcp/index.md) — the controls these resources should satisfy.
- [Secrets](https://github.com/greenblacked/security-toolbox/blob/main/docs/secrets/index.md) — why state needs the same protection as a credential store.
- [IaC Review](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/iac-review/SKILL.md) — the review procedure for a plan.
