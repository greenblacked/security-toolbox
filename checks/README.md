# Checks

Read-only report scripts and checklists. Nothing here changes a cluster, project or repository. Each script works against live state or against saved JSON (`--file`, `--pods`, ...) so you can run it on an export from a locked-down environment, and each ships good/bad fixtures; `./checks/test.sh` runs them all.

| Path | What it covers | Run |
| --- | --- | --- |
| [`gke/`](gke/) | GKE cluster hardening checklist and report: Workload Identity, Shielded Nodes, Binary Authorization, NetworkPolicy, private nodes, node service accounts, upgrades | `checks/gke/gke-report.sh --cluster prod --location europe-west1` |
| [`kubernetes/`](kubernetes/) | CIS Kubernetes Benchmark 5.1 / 5.2 workload controls: privileged, host namespaces, hostPath, root and privilege escalation across init, regular and ephemeral containers of Pods and workload templates, plus `cluster-admin` bindings | `checks/kubernetes/cis-workload-report.sh` |
| [`github/`](github/) | GitHub Actions hardening note: SHA pinning, permissions, `pull_request_target`, `persist-credentials`, expression injection, OIDC | read [`actions-hardening.md`](github/actions-hardening.md) |

Exit codes: `0` clean (warnings allowed), `1` at least one failure, `2` usage error. Dependencies: `bash`, `jq`, plus `gcloud` or `kubectl` for live mode.

For Terraform and manifest policies evaluated before deploy, see [`../policies/`](../policies/).
