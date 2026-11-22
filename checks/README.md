# Checks

Read-only report scripts and checklists. Nothing here changes a cluster, project or repository. Each script works against live state or against saved JSON (`--file`, `--pods`, ...) so you can run it on an export from a locked-down environment, and each ships good/bad fixtures; `./checks/test.sh` runs them all.

| Path | What it covers | Run |
| --- | --- | --- |
| [`gke/`](gke/) | GKE cluster hardening checklist and report: Workload Identity, Shielded Nodes, Binary Authorization, NetworkPolicy, private nodes, node service accounts, upgrades | `checks/gke/gke-report.sh --cluster prod --location europe-west1` |
| [`kubernetes/`](kubernetes/) | CIS Kubernetes Benchmark 5.1 / 5.2 workload controls: privileged, host namespaces, hostPath, root and privilege escalation across init, regular and ephemeral containers of Pods and workload templates, plus `cluster-admin` bindings | `checks/kubernetes/cis-workload-report.sh` |
| [`gcp/`](gcp/) | Project IAM baseline: public members, standing basic roles, the default compute service account holding Editor, project-wide impersonation and security admin, individual user bindings, and members from outside a given domain | `checks/gcp/iam-report.sh --project prod --domain example.com` |
| [`github/`](github/) | GitHub Actions hardening note: SHA pinning, permissions, `pull_request_target`, `persist-credentials`, expression injection, OIDC | read [`actions-hardening.md`](github/actions-hardening.md) |

Exit codes: `0` clean (warnings allowed), `1` at least one failure, `2` usage error. Dependencies: `bash`, `jq`, plus `gcloud` or `kubectl` for live mode.

For Terraform and manifest policies evaluated before deploy, see [`../policies/`](../policies/).

## How a check is meant to be used

1. **Run it read-only first.** Every script is a report: it prints `PASS`, `FAIL` or `WARN` per control and exits non-zero on a failure. Nothing is remediated for you, and nothing needs write access.
2. **Export and attach the output.** A check that ran against a saved export is reproducible by the person reviewing the ticket, which a live run against a cluster that has since changed is not.
3. **Read `WARN` as a decision, not noise.** A `WARN` is a control that is sometimes legitimately off. Leaving it off is fine if the reason is written down; leaving it off silently is how it stays off for two years.
4. **Re-run after the fix.** The output is the evidence, and a fix nobody re-checked is a claim.

## Why a failure count is asserted in tests

Each bad fixture must trip an exact number of controls (`checks/test.sh` greps for `failures: N`). Without that, a control that stops working — a renamed JSON field, a `jq` path that returns null — passes silently, because a report that finds nothing still exits 0. The count is the cheapest way to notice that a check has gone blind.

## What a check is not

- **Not a compliance certificate.** It reads one API surface at one moment. Control-plane and node items that need host access (CIS sections 1 to 4) are out of scope and need `kube-bench` on a self-managed cluster.
- **Not enforcement.** A report can be ignored. The enforcement counterparts are Pod Security Admission and the admission policy engine for workloads, organisation policy and IAM deny policies for GCP, and the policies in [`../policies/`](../policies/) for the pull request.
- **Not a replacement for the telemetry.** A clean report says the configuration is right, not that nothing happened. Use logs and runtime detection for what a static read cannot see.

## Adding a check

1. One directory per target, with a script that accepts `--file` (or `--pods`, `--bindings`) for offline use and a live mode that needs the narrowest read permission available.
2. A `README.md` in the same directory: what it checks, what it does not, and the exact command.
3. `fixtures/<name>-good.json` and `fixtures/<name>-bad.json`. The good one must exit 0; the bad one must exit 1 and trip an asserted number of controls.
4. Wire both into `checks/test.sh` and add the row above.
5. Keep the script POSIX-ish bash with `set -Eeuo pipefail`, quote every expansion, and fail with exit `2` on a usage error so a pipeline can tell a mistake from a finding.
