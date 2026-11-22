# Kubernetes / GKE

## Cluster (GKE)

[`checks/gke/gke-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/gke-report.sh) reports the cluster-level controls from `gcloud container clusters describe`; the [checklist](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/README.md) explains each one. The Rust `stb gke` command reports the same controls offline from saved JSON or stdin, as text, JSON or SARIF 2.1.0:

```bash
cd checks && cargo build --release --locked
target/release/stb gke --file prod.json --format sarif > gke.sarif
```

- **Workload Identity Federation for GKE** on the cluster and `GKE_METADATA` on every node pool, so pods never see the node service account.
- **Shielded GKE Nodes** with integrity monitoring (and Secure Boot where drivers allow).
- **Private nodes**, control-plane authorised networks, no legacy ABAC, no static client certificate.
- **Dedicated node service account** with `roles/container.defaultNodeServiceAccount` only.
- **Release channel and auto-upgrade** with maintenance windows.
- **Binary Authorization** in dry-run, then enforce, once images are signed in CI.
- **NetworkPolicy enforcement** via GKE Dataplane V2, then default-deny per namespace.

## Workloads

Enforce the Pod Security Standards `restricted` profile with Pod Security Admission:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

A compliant container sets `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`, and ideally `readOnlyRootFilesystem: true`, plus resource requests and limits.

- **Before deploy:** [`policies/opa/kubernetes`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/kubernetes/pod_security.rego) with Conftest on rendered manifests in CI (Pods and Deployment, StatefulSet, DaemonSet, ReplicaSet, Job and CronJob templates; init, regular and ephemeral containers).
- **Running cluster:** [`checks/kubernetes/cis-workload-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/kubernetes/cis-workload-report.sh) for CIS 5.1 / 5.2 workload controls (privileged, host namespaces, hostPath, root, privilege escalation in init, regular and ephemeral containers, `cluster-admin` bindings), on live Pods or exported workload manifests.
- **Node and control-plane items** (CIS sections 1 to 4): kube-bench on self-managed clusters; on GKE the control plane is provider-managed.

## RBAC

- No `cluster-admin` bindings outside break-glass groups; CI deployers get namespace-scoped Roles.
- Avoid wildcard verbs/resources and `escalate`, `bind`, `impersonate` grants; treat `create pods` and `get secrets` as privileged.
- `automountServiceAccountToken: false` on pods that do not call the API.
- On GKE, map Google Groups to RBAC (Google Groups for RBAC) instead of binding individual users.

## Network

Start every namespace with default-deny ingress and egress, then allow DNS and the specific flows each workload needs. A NetworkPolicy without an enforcing dataplane does nothing, so verify enforcement first.

## Images and supply chain

Pin images by digest, build from minimal bases, scan in CI with a severity gate, sign with cosign and verify at admission (Binary Authorization, Kyverno or Gatekeeper). See the `image-hardening` skill.

## Secrets

Use Secret Manager via the Secret Manager CSI driver or External Secrets with Workload Identity rather than long-lived Kubernetes Secrets copied from a laptop. Enable application-layer secrets encryption (Cloud KMS) on GKE.
