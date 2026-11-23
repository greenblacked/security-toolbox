# GCP IAM baseline

[`iam-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gcp/iam-report.sh) reads a project IAM policy and reports the grants that make every other control pointless: public members, standing basic roles, and the default compute service account holding Editor. It changes nothing.

```bash
# Live project, with the domain that members must belong to
checks/gcp/iam-report.sh --project prod-project --domain example.com
# From an export, for a locked-down environment
gcloud projects get-iam-policy prod-project --format=json > policy.json
checks/gcp/iam-report.sh --file policy.json --domain example.com
```

Exit codes: `0` clean (warnings allowed), `1` at least one failure, `2` usage, fetch, or invalid-input error. Use a full unfiltered export. A policy with an empty bindings array, or an etag with omitted bindings, reports zero direct grants. An ambiguous document or incomplete conditional policy export produces no control results. Needs `bash`, `jq`, and `gcloud` with `resourcemanager.projects.getIamPolicy` unless `--file` is used.

## What it checks

| Control | Level | Why |
| --- | --- | --- |
| No public members | FAIL | `allUsers` or `allAuthenticatedUsers` on any role exposes the project to the internet |
| No unconditional basic roles | FAIL | `roles/owner` and `roles/editor` grant thousands of permissions; Google IAM does not allow conditions on legacy basic roles |
| No unconditional `roles/viewer` | WARN | Grants broad read access. Prefer service-specific read roles |
| Default compute SA holds no basic role | FAIL | Anything running as the default account inherits it, including workloads nobody reviewed |
| No project-wide token creator | WARN | `roles/iam.serviceAccountTokenCreator` at project scope can impersonate every account in it |
| No project-wide security admin | WARN | `roles/iam.securityAdmin` can grant itself anything; it belongs in a break-glass group |
| No bindings to individual users | WARN | User bindings are invisible to an access review that reads the identity provider |
| Members inside the given domain | WARN | A member from another domain is either a partner grant or a mistake; only checked with `--domain` |

## What it does not do

- It reads the policy document, not effective access. Inherited folder and organisation bindings, IAM conditions evaluated at request time, and deny policies are not applied.
- It cannot see service-account keys, workload identity trust policies or organisation policy constraints. Those are separate APIs; the guide covers them and the `access-review` skill covers the evidence collection.
- It reports grants, not use. A binding with no last-authenticated data behind it is the finding the review is looking for, and that needs the telemetry, not the policy.

For REST exports, request IAM policy version 3 so conditions are preserved. [Google IAM policy versions](https://docs.cloud.google.com/iam/docs/allow-policies) and [IAM Conditions](https://docs.cloud.google.com/iam/docs/conditions-overview) describe these constraints.

## Fixtures

`fixtures/policy-good.json` passes and `fixtures/policy-bad.json` fails three controls, with the rest warning. `checks/test.sh` asserts both, and asserts the exact failure count so a new check cannot silently pass.
