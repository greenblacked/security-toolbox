# GKE hardening

`gke-report.sh` checks one cluster's `gcloud container clusters describe --format=json` output. It needs only `container.clusters.get` (for example `roles/container.clusterViewer`).

```bash
checks/gke/gke-report.sh --cluster prod --location europe-west1 --project my-project
# or offline
gcloud container clusters describe prod --location europe-west1 --format=json > prod.json
checks/gke/gke-report.sh --file prod.json
```

The same report is available offline from the Rust `stb` binary, which also writes JSON and SARIF 2.1.0 (see [`../README.md`](../README.md#stb-rust-port)):

```bash
(cd checks && cargo build --release --locked)
checks/target/release/stb gke --file prod.json --format sarif > gke.sarif
```

`stb gke` reports the same controls with the same levels and messages, and gives the same failure count on the fixtures (`fixtures/cluster-bad.json`: 9 failures and 5 warnings; `fixtures/cluster-good.json`: none). Its rule ids are listed below.

## Checklist

FAIL items are blockers for a production cluster; WARN items need a recorded reason if left off.

| Control | Level | Why | How | `stb` rule id |
| --- | --- | --- | --- | --- |
| Workload Identity Federation for GKE | FAIL | Pods get short-lived Google credentials for a specific Kubernetes service account instead of the node's identity or an exported key | `--workload-pool=PROJECT_ID.svc.id.goog` on the cluster, `--workload-metadata=GKE_METADATA` on every node pool, then bind `roles/iam.workloadIdentityUser` per KSA | `gke-workload-identity` |
| GKE metadata server on node pools | FAIL | Without it, pods can read the node service account token from the Compute metadata server | `--workload-metadata=GKE_METADATA` | `gke-metadata-server` |
| Shielded GKE Nodes | FAIL | Node identity is verified, so a compromised pod cannot impersonate a node to join the cluster | `--enable-shielded-nodes` (default on new clusters) | `gke-shielded-nodes` |
| Integrity monitoring | FAIL | Detects boot-level tampering on nodes | `--shielded-integrity-monitoring` on node pools | `gke-integrity-monitoring` |
| Secure Boot | WARN | Blocks unsigned kernel modules; breaks some third-party drivers, so test first | `--shielded-secure-boot` on node pools | `gke-secure-boot` |
| Binary Authorization | WARN | Only images that meet a policy (allowed registries, attestations from your build) are admitted | `--binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE`, start the policy in dry-run, then enforce; pair with image signing (see the `image-hardening` skill) | `gke-binary-authorization` |
| NetworkPolicy enforcement | FAIL | Without an enforcing dataplane, `NetworkPolicy` objects are silently ignored | GKE Dataplane V2 (`--enable-dataplane-v2`, default for Autopilot) or `--enable-network-policy`; then a default-deny policy per namespace | `gke-network-policy` |
| Private nodes | FAIL | Nodes without external IPs are not directly reachable from the internet | `--enable-private-nodes`, Cloud NAT for egress | `gke-private-nodes` |
| Control plane authorised networks | WARN | Limits who can reach the Kubernetes API endpoint | `--enable-master-authorized-networks --master-authorized-networks=CIDR,...` or DNS-based endpoint with IAM | `gke-authorised-networks` |
| Legacy ABAC disabled | FAIL | ABAC grants bypass RBAC | `--no-enable-legacy-authorization` | `gke-legacy-abac` |
| No static client certificate | FAIL | A client certificate is a non-revocable cluster credential | Create clusters without `--issue-client-certificate`; rotate credentials if one exists | `gke-client-certificate` |
| Dedicated node service account | FAIL | The Compute default SA usually holds Editor on the project | Node SA with `roles/container.defaultNodeServiceAccount` only | `gke-node-service-account` |
| Release channel | WARN | Security patches arrive on a schedule instead of when someone remembers | `--release-channel=regular` (or `stable`) | `gke-release-channel` |
| Node auto-upgrade | WARN | Keeps node images patched | `--enable-autoupgrade` on node pools, with maintenance windows | `gke-node-auto-upgrade` |

## NetworkPolicy starting point

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Add explicit allows per workload, including egress to `kube-dns` on port 53.

Workload-level controls (privileged pods, hostPath, root) are covered by [`../kubernetes/`](../kubernetes/) and the Pod Security Admission `restricted` profile. Not covered here: Security Command Center findings, GKE security posture dashboard, Autopilot-specific defaults (most of the above are already enforced on Autopilot).
