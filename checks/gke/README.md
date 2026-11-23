# GKE hardening

`gke-report.sh` checks one cluster's `gcloud container clusters describe --format=json` output. It needs only `container.clusters.get` (for example `roles/container.clusterViewer`).

```bash
checks/gke/gke-report.sh --cluster prod --location europe-west1 --project my-project
# or offline
gcloud container clusters describe prod --location europe-west1 --format=json > prod.json
checks/gke/gke-report.sh --file prod.json
```

## Checklist

Exit 0 means no FAIL. Review WARN results, including controls with unavailable evidence. Exit 1 means at least one FAIL, and exit 2 means the cluster export was invalid or unavailable. Supply either a file or a live cluster and location. Redact certificate keys and other credentials from any cluster export you retain.

The report prefers modern fields where present and honours explicit false. Private-node coverage comes from listed pool settings and the cluster defaults, with a pool override taking precedence. Empty or omitted pool lists leave pool-level coverage unverified for both Standard and Autopilot. When direct IP access is explicitly disabled, IP authorised networks are N/A. Verify DNS endpoint access separately. The report checks configuration. Independently verify actual NetworkPolicy enforcement and whether Binary Authorization rules are enforcing or in dry-run mode.

| Control | Level | Why | How |
| --- | --- | --- | --- |
| Workload Identity Federation for GKE | FAIL | Pods get short-lived Google credentials for a specific Kubernetes service account instead of the node's identity or an exported key | `--workload-pool=PROJECT_ID.svc.id.goog` on the cluster, `--workload-metadata=GKE_METADATA` on every node pool, then bind `roles/iam.workloadIdentityUser` per KSA |
| GKE metadata server on node pools | FAIL | Without it, pods can read the node service account token from the Compute metadata server | `--workload-metadata=GKE_METADATA` |
| Shielded GKE Nodes | FAIL | Node identity is verified, so a compromised pod cannot impersonate a node to join the cluster | `--enable-shielded-nodes` (default on new clusters) |
| Integrity monitoring | FAIL | Detects boot-level tampering on nodes | `--shielded-integrity-monitoring` on node pools |
| Secure Boot | WARN | Blocks unsigned kernel modules; breaks some third-party drivers, so test first | `--shielded-secure-boot` on node pools |
| Binary Authorization | WARN | Only images that meet a policy (allowed registries, attestations from your build) are admitted | `--binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE`, start the policy in dry-run, then enforce; pair with image signing (see the `image-hardening` skill) |
| NetworkPolicy configuration | FAIL | Without an enforcing dataplane, `NetworkPolicy` objects are silently ignored | GKE Dataplane V2 (`--enable-dataplane-v2`, default for Autopilot) or `--enable-network-policy`; then a default-deny policy per namespace |
| Private nodes | FAIL | Nodes without external IPs are not directly reachable from the internet | `--enable-private-nodes`, Cloud NAT for egress |
| Control plane authorised networks | WARN | Limits who can reach the Kubernetes API endpoint | `--enable-master-authorized-networks --master-authorized-networks=CIDR,...` or DNS-based endpoint with IAM |
| Legacy ABAC disabled | FAIL | ABAC grants bypass RBAC | `--no-enable-legacy-authorization` |
| No static client certificate issuance | FAIL / WARN when unavailable | A client certificate is a non-revocable cluster credential | Create clusters without `--issue-client-certificate`; rotate credentials if one exists |
| Dedicated node service account | FAIL | The Compute default SA usually holds Editor on the project | Node SA with `roles/container.defaultNodeServiceAccount` only |
| Release channel | WARN | Security patches arrive on a schedule instead of when someone remembers | `--release-channel=regular` (or `stable`) |
| Node auto-upgrade | WARN | Keeps node images patched | `--enable-autoupgrade` on node pools, with maintenance windows |

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

Workload-level controls (privileged pods, hostPath, root) are covered by [`../kubernetes/`](../kubernetes/) and the Pod Security Admission `restricted` profile. Security Command Center findings, the GKE security posture dashboard and controls unavailable from the cluster description require separate evidence.
