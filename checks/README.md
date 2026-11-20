# Checks

Read-only report scripts and checklists. Nothing here changes a cluster, project or repository. Each script works against live state or against saved JSON (`--file`, `--pods`, ...) so you can run it on an export from a locked-down environment, and each ships good/bad fixtures; `./checks/test.sh` runs them all.

| Path | What it covers | Run |
| --- | --- | --- |
| [`gke/`](gke/) | GKE cluster hardening checklist and report: Workload Identity, Shielded Nodes, Binary Authorization, NetworkPolicy, private nodes, node service accounts, upgrades | `checks/gke/gke-report.sh --cluster prod --location europe-west1`, or offline `stb gke --file prod.json` |
| [`kubernetes/`](kubernetes/) | CIS Kubernetes Benchmark 5.1 / 5.2 workload controls: privileged, host namespaces, hostPath, root and privilege escalation across init, regular and ephemeral containers of Pods and workload templates, plus `cluster-admin` bindings | `checks/kubernetes/cis-workload-report.sh` |
| [`github/`](github/) | GitHub Actions hardening note: SHA pinning, permissions, `pull_request_target`, `persist-credentials`, expression injection, OIDC | read [`actions-hardening.md`](github/actions-hardening.md) |

Exit codes: `0` clean (warnings allowed), `1` at least one failure, `2` usage error. Dependencies: `bash`, `jq`, plus `gcloud` or `kubectl` for live mode.

## `stb`: Rust port

`stb` is a single binary that runs the checks offline against JSON you already exported. It never runs `gcloud` or `kubectl`, calls a cloud API or opens a network connection. It lives in the Cargo workspace in this directory ([`Cargo.toml`](Cargo.toml), crate [`stb/`](stb/)); the toolchain is pinned in [`rust-toolchain.toml`](rust-toolchain.toml), so `rustup` installs the right version on first use.

```bash
cd checks
cargo build --release --locked
cargo test

# GKE: same controls, levels and messages as gke/gke-report.sh
gcloud container clusters describe prod --location europe-west1 --format=json > prod.json
target/release/stb gke --file prod.json                   # text, same lines as the shell report
target/release/stb gke --file prod.json --format json     # summary plus one result per control
target/release/stb gke --file prod.json --format sarif    # SARIF 2.1.0, one result per FAIL or WARN
gcloud container clusters describe prod --location europe-west1 --format=json | target/release/stb gke
```

`--file -` or no `--file` reads stdin. Exit codes match the scripts: `0` clean (warnings allowed), `1` at least one failure, `2` usage or input error, including unreadable files, malformed JSON and input that is not a JSON object. In SARIF, FAIL controls are `error` results and WARN controls are `warning` results.

Only `gke` is ported so far. The shell scripts stay the reference until the port is complete; `./checks/test.sh` still runs them.

For Terraform and manifest policies evaluated before deploy, see [`../policies/`](../policies/).
