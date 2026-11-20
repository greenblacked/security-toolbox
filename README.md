# Security Toolbox

[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Read-only security reports for GKE and Kubernetes, policy-as-code for GCP Terraform and Kubernetes manifests, and practical guides for GitHub Actions, secrets, and supply chain security. The toolbox complements [ops-toolbox](https://github.com/greenblacked/ops-toolbox).

[Browse the documentation site](https://security.szolotov.com)

## Quick start with offline fixtures

From a fresh clone, run the report examples with `bash` and `jq`. Install `conftest` for the Terraform policy example. All three use files from the repository and require no cloud credentials.

```bash
git clone https://github.com/greenblacked/security-toolbox.git
cd security-toolbox

./checks/gke/gke-report.sh --file checks/gke/fixtures/cluster-good.json

./checks/kubernetes/cis-workload-report.sh \
  --pods checks/kubernetes/fixtures/pods-good.json \
  --bindings checks/kubernetes/fixtures/bindings-good.json

conftest test --policy policies/opa/terraform --namespace terraform.gcp \
  policies/opa/terraform/fixtures/plan-good.json
```

The GKE report exits `1` if any control reports `FAIL`. A `WARN` alone leaves the exit code at `0`. The Kubernetes workload report exits `1` when it reports findings. It covers selected CIS controls in sections 5.1 and 5.2.

## Run against your infrastructure

### GKE cluster

Use an authenticated `gcloud` account with `container.clusters.get`. Set `GCP_PROJECT`, `GKE_CLUSTER`, and `GKE_LOCATION` to the intended project ID, cluster name, and region or zone.

```bash
./checks/gke/gke-report.sh \
  --project "${GCP_PROJECT:?Set GCP_PROJECT to the Google Cloud project ID}" \
  --cluster "${GKE_CLUSTER:?Set GKE_CLUSTER to the cluster name}" \
  --location "${GKE_LOCATION:?Set GKE_LOCATION to the region or zone}"
```

### Kubernetes workloads

Use `kubectl` credentials that can list Pods across namespaces and list ClusterRoleBindings. Set `KUBE_CONTEXT` to the intended context from `kubectl config get-contexts`. Both requests use that context explicitly.

```bash
(
  set -eu
  : "${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended kubeconfig context}"
  report_dir="$(mktemp -d)"
  trap 'rm -rf "$report_dir"' EXIT

  kubectl --context "$KUBE_CONTEXT" get pods -A -o json > "$report_dir/pods.json"
  kubectl --context "$KUBE_CONTEXT" get clusterrolebindings -o json > "$report_dir/bindings.json"
  ./checks/kubernetes/cis-workload-report.sh \
    --pods "$report_dir/pods.json" --bindings "$report_dir/bindings.json"
)
```

### Saved Terraform plan

Use Terraform and Conftest. Set `TF_PLAN` to the path of a saved plan produced by `terraform plan -out`. The example writes plan JSON, which can contain sensitive values, to a temporary directory and removes it on exit.

```bash
(
  set -eu
  : "${TF_PLAN:?Set TF_PLAN to the saved Terraform plan path}"
  plan_dir="$(mktemp -d)"
  trap 'rm -rf "$plan_dir"' EXIT

  terraform show -json "$TF_PLAN" > "$plan_dir/plan.json"
  conftest test --policy policies/opa/terraform --namespace terraform.gcp "$plan_dir/plan.json"
)
```

## Guides and tools

| Area | Guide | Tools and references |
| --- | --- | --- |
| Kubernetes and GKE | [Kubernetes and GKE hardening](docs/kubernetes/index.md) | [GKE reports](checks/gke/), [workload reports](checks/kubernetes/), [pod security policies](policies/opa/kubernetes/) |
| Google Cloud | [GCP security baseline](docs/gcp/index.md) | [GCP Terraform policies](policies/opa/terraform/) |
| Terraform | [Terraform and IaC checks](docs/terraform/index.md) | [Conftest policies](policies/opa/terraform/), [Checkov checks](policies/checkov/) |
| GitHub Actions | [GitHub security baseline](docs/github/index.md) | [Actions hardening checklist](checks/github/actions-hardening.md) |
| Secrets | [Secrets management](docs/secrets/index.md) | [Secret rotation](plugins/security/skills/secret-rotation/SKILL.md) |
| Security skills | [Skill catalog](plugins/security/skills/) | Procedures for IaC review, image and host hardening, threat modelling, dependency triage, and incident response |

## Local validation

The [report tests](checks/test.sh) need Bash and jq. The [policy tests](policies/test.sh) need Bash, OPA, Conftest, and Python 3. The runner skips the Checkov tests when Checkov is unavailable.

```bash
./checks/test.sh
./policies/test.sh
```

Build the documentation guides locally with Node.js and npm.

```bash
npm ci --ignore-scripts
node scripts/build_site.cjs
```

See the [CI and deployment runbook](docs/ci.md) for the site dry run, environment promotion, release verification, and rollback. Use the [security policy](SECURITY.md) to report vulnerabilities privately.
