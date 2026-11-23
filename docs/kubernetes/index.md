# Kubernetes / GKE

**Who this is for:** platform engineers who run GKE clusters and the teams deploying to them. You should be comfortable with `kubectl`, RBAC objects and a pod spec.

Everything on this page can be checked read-only before you change anything.
[`checks/gke/gke-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/gke-report.sh) reports the cluster controls and
[`checks/kubernetes/cis-workload-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/kubernetes/cis-workload-report.sh)
reports the workloads. Both run against live state or a saved export, so you can see the current posture before deciding what to change.

## Cluster (GKE)

[`checks/gke/gke-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/gke-report.sh) reports the cluster-level controls from `gcloud container clusters describe`; the [checklist](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/README.md) explains each one.

- **Workload Identity Federation for GKE** on the cluster and `GKE_METADATA` on every node pool, for eligible workloads. Review host-network workloads and node permissions separately.
- **Shielded GKE Nodes** with integrity monitoring (and Secure Boot where drivers allow).
- **Private nodes**, control-plane authorised networks, no legacy ABAC, no static client certificate.
- **Dedicated node service account** with `roles/container.defaultNodeServiceAccount` as a baseline. Scope any additional permissions, such as private registry reads, to the resources needed.
- **Release channel and auto-upgrade** with maintenance windows.
- **Binary Authorization** in dry-run, then enforce, once images are signed in CI.
- **NetworkPolicy enforcement** via GKE Dataplane V2, then default-deny per namespace.

### Enforce the list at the organisation

Most of the bullets above can be a constraint instead of a review. The `container.managed.*` organisation policy family covers the cluster controls directly — `enablePrivateNodes`, `enableShieldedNodes`, `enableNetworkPolicy`, `enableWorkloadIdentityFederation`, `enableBinaryAuthorization`, `enableSecretsEncryption`, `disableABAC`, `disableLegacyClientCertificateIssuance`, `disallowDefaultComputeServiceAccount`, `denyServiceExternalIPs`, `enableGoogleGroupsRBAC`.

A cluster created without them then fails to create, rather than appearing in a report next quarter. A constraint keeps working when the team that created the cluster has moved on.

### Upgrade blockers worth knowing now

- **Identity Service for GKE is removed in 1.37.** A cluster that still has it enabled cannot be created or upgraded. Migrate OIDC to Workforce Identity Federation before that upgrade window arrives, not during it.
- **GKE Sandbox (gVisor)** puts a user-space kernel between the container and the host for untrusted or multi-tenant workloads; **Confidential GKE Nodes** encrypt memory in use. Neither replaces pod hardening — they bound the blast radius when it fails.

### Control plane exposure

The control plane is the cluster's administrative API, and its reachability is a security control, not a convenience setting.

- `master_authorized_networks_config` names the CIDRs that may reach the API server. Keep it to bastion and CI egress ranges; a `/0` entry undoes the rest of the list.
- `enable_private_endpoint` removes the public API address entirely. The cost is that every client needs private routing: a bastion, Cloud Interconnect, or an in-VPC runner.
- `enable_private_nodes` keeps node IPs internal; combine it with Cloud NAT so nodes can still pull images.
- GKE Kubernetes API audit events generally use `k8s.io`. Deployment deletion is an Admin Activity event, which is always enabled. Configure `ADMIN_READ`, `DATA_READ` or `DATA_WRITE` for investigation needs that require Data Access. Kubernetes audit levels separately determine which request or response fields are logged. Send security evidence to a separately administered sink and restrict access to raw payloads and command arguments. [GKE audit logging](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/audit-logging) · [GKE audit policy](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/audit-policy).

### Node pools

Split pools by trust and by change rate, not by convenience. A pool that runs untrusted batch work should not share a kernel, a node identity or an eviction budget with the ingress controllers.

- `image_type = "COS_CONTAINERD"` — the minimal, signed node image. Docker-based images are gone on current versions.
- **GKE Sandbox** (`sandbox_type = "gvisor"`) for multi-tenant or untrusted workloads: a user-space kernel between the container and the host.
- `auto_repair` and `auto_upgrade` on; surge settings that keep capacity during a rolling upgrade.
- Taints and tolerations so a workload lands only on the pool built for it, and `nodeSelector`/affinity so it does not drift.
- One node service account per pool where the pools have different cloud permissions. Keep the node identity least-privileged even with Workload Identity Federation. GKE still uses the node identity for image pulls, and host-network workloads require separate review. [Workload identity behavior](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity).

```bash
# Control-plane and cluster posture, read-only
gcloud container clusters describe CLUSTER --location LOCATION \
  --format='value(privateClusterConfig.enablePrivateNodes,privateClusterConfig.enablePrivateEndpoint)'
gcloud container clusters describe CLUSTER --location LOCATION \
  --format='value(masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock)'
gcloud container clusters describe CLUSTER --location LOCATION \
  --format='value(workloadIdentityConfig.workloadPool,shieldedNodes.enabled,releaseChannel.channel)'
gcloud container clusters describe CLUSTER --location LOCATION \
  --format='value(binaryAuthorization.evaluationMode,addonsConfig.networkPolicyConfig.disabled)'
# Every node pool must use GKE_METADATA
gcloud container node-pools list --cluster CLUSTER --location LOCATION \
  --format='table(name,config.workloadMetadataConfig.mode,config.imageType)'
```

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

For Linux workloads, the Restricted standard requires non-root execution, disabled privilege escalation, dropped capabilities, and a suitable seccomp profile. The example adds a read-only root filesystem and resource requests and limits as separate hardening measures. [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/).

### A pod that passes `restricted`

```yaml
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: app
      image: registry.example.com/app@sha256:...
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: [ALL]}
      resources:
        requests: {cpu: 100m, memory: 128Mi}
        limits: {cpu: 500m, memory: 256Mi}
      volumeMounts:
        - {name: tmp, mountPath: /tmp}
  volumes:
    - name: tmp
      emptyDir: {}
```

- `runAsNonRoot` without `runAsUser` only works when the image declares a numeric user; a `USER app` by name fails the check.
- `readOnlyRootFilesystem: true` needs an `emptyDir` wherever the process writes, or it crash-loops on first start.
- Set `automountServiceAccountToken: false` for Pods that do not need Kubernetes API credentials. The Pod setting takes precedence over its ServiceAccount. Review explicitly projected tokens separately. [Service account configuration](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/).
- `seccompProfile: RuntimeDefault` is the single highest-value line here: it blocks whole syscall families that container escapes rely on.

### Admission

Pod Security Admission is built in and namespace-scoped; it has three profiles (`privileged`, `baseline`, `restricted`) and three modes (`enforce`, `audit`, `warn`). Run `warn` and `audit` first, fix what they report, then `enforce`.

For anything PSA cannot express — registry allow-lists, required labels, image signature verification, disallowed `hostPath` prefixes — use a policy engine: Kyverno, Gatekeeper, or a ValidatingAdmissionPolicy. Whichever you pick:

- Start in audit mode and count what would be denied before enforcing.
- Exempt by namespace with a named owner and a date, not by adding `privileged` to the whole cluster.
- Keep the policies in git and test them against fixtures in CI, the way [`policies/opa/kubernetes`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/kubernetes/pod_security.rego) is tested here.

### Before and after deploy

- **Before deploy:** [`policies/opa/kubernetes`](https://github.com/greenblacked/security-toolbox/blob/main/policies/opa/kubernetes/pod_security.rego) with Conftest on rendered manifests in CI (Pods and Deployment, StatefulSet, DaemonSet, ReplicaSet, Job and CronJob templates; init, regular and ephemeral containers).
- **Running cluster:** [`checks/kubernetes/cis-workload-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/kubernetes/cis-workload-report.sh) for CIS 5.1 / 5.2 workload controls (privileged, host namespaces, hostPath, root, privilege escalation in init, regular and ephemeral containers, `cluster-admin` bindings), on live Pods or exported workload manifests.
- **Node and control-plane items** (CIS sections 1 to 4): kube-bench on self-managed clusters; on GKE the control plane is provider-managed.

## RBAC

RBAC is where a small mistake becomes a cluster compromise. The verbs to treat as root-equivalent:

| Grant | Why it is root |
| --- | --- |
| `create pods` in any namespace | Run an image with any service account, mount any secret, or schedule onto any node |
| `get`/`list secrets` | Every credential in that namespace |
| `pods/exec`, `pods/attach` | A shell in any running container, with its tokens and volumes |
| `escalate` on roles, `bind` on rolebindings | Grant yourself anything |
| `impersonate` on users, groups, serviceaccounts | Become anyone, including `system:admin` |
| `create` on `daemonsets` or access to `nodes/proxy`, including `get` | Treat node-level access as highly privileged |
| `patch` on `validatingwebhookconfigurations` | Disable your own admission controls |

- No `cluster-admin` bindings outside break-glass groups; CI deployers get namespace-scoped Roles.
- Avoid wildcard verbs/resources and `escalate`, `bind`, `impersonate` grants; treat `create pods` and `get secrets` as privileged.
- `automountServiceAccountToken: false` on pods that do not call the API.
- On GKE, map Google Groups to RBAC (Google Groups for RBAC) instead of binding individual users.
- Bind to groups, and keep the group membership in the identity provider where it is audited and reviewed. A RoleBinding to a user is invisible to an access review that reads the IdP.
- Prefer `RoleBinding` in the namespace over `ClusterRoleBinding`; a ClusterRole can still be bound namespace-scoped.
- Modern Kubernetes normally mounts a short-lived projected service-account token for the API server when automounting is enabled. Use an explicit projection with the intended audience when a workload needs a token for another relying party, and request an appropriate lifetime.

```bash
# Who can do what, for one identity
kubectl auth can-i --list --as=system:serviceaccount:app:deployer -n app
# Everyone holding cluster-admin
kubectl get clusterrolebindings -o json \
  | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .subjects[]? | "\(.kind)/\(.namespace // "-")/\(.name)"'
# Pods without an explicit Pod-level opt-out; also check the ServiceAccount and actual volume mounts
kubectl get pods -A -o json \
  | jq -r '.items[] | select(.spec.automountServiceAccountToken != false) | "\(.metadata.namespace)/\(.metadata.name)"'
```

## Network

Start with a narrowly scoped canary. Standard NetworkPolicy requires an enforcing dataplane. Policies are additive, and a flow must be allowed by both applicable source egress and destination ingress rules. A single peer containing both selectors matches Pods in the selected namespaces. Two separate peers allow the union. The example assumes Pod-backed DNS using the shown resolver labels. Verify the DNS path on your cluster before using it.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: app}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: app}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
```

### Verify the rollout

1. Inventory DNS, workload identity, application traffic, ingress, monitoring and load-balancer backends. Check the effective resolver from the workload. NodeLocal DNSCache and managed DNS can use a different path from the example.
2. Roll out the complete approved allow set in a canary namespace. An allow policy can begin isolating Pods for its selected direction as soon as it takes effect. Use fresh connections to check an expected allowed flow and an expected denied flow against the same healthy service.
3. For Workload Identity Federation on GKE, preserve the metadata server egress for the cluster's dataplane. Use Google's network policy port table, which includes ports needed during upgrades. Validate a narrow authorized Google Cloud API request from a fresh canary workload without printing its token.
4. Verify DNS on TCP and UDP, application readiness, load balancer backend health, and metrics collection separately. Kubernetes reports depend on the dataplane, and green GKE kubelet probes do not establish Pod-to-Pod reachability. If any expected flow fails, revert the reviewed policy change and repeat the checks.

Sources: [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) · [GKE NetworkPolicy and Workload Identity](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy#network_policy_and_workload_identity_federation_for_gke) · [GKE NodeLocal DNSCache](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/nodelocal-dns-cache) · [GKE network policy logging](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy-logging).

## Images and supply chain

Pin images by digest, build from minimal bases, scan in CI with a severity gate, sign with cosign and verify at admission (Binary Authorization, Kyverno or Gatekeeper). See the [`image-hardening`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/image-hardening/SKILL.md) skill.

- A tag is mutable: `:1.4.2` today is not the image it was yesterday. `image@sha256:...` is.
- Generate an SBOM at build time and keep it beside the digest, so an advisory can be matched to running workloads.
- Verify the signature in the admission path, not only in CI. A cluster that trusts any image is one compromised registry credential away from running anything.
- Deny `latest` explicitly: it hides the fact that a rollback will pull different code.

## Secrets

Use Secret Manager via the Secret Manager CSI driver or External Secrets with Workload Identity rather than long-lived Kubernetes Secrets copied from a laptop. Enable application-layer secrets encryption (Cloud KMS) on GKE.

- A Kubernetes Secret is base64, not encryption. Anyone with `get secrets` in the namespace, or read access to etcd, has the plaintext.
- Mount secrets as files where the application can read them at start, and prefer a client that re-reads on rotation over an environment variable that is fixed for the process lifetime.
- `immutable: true` on Secrets that never change prevents accidental edits and reduces API server load.

## Runtime and detection

Configuration stops the known-bad deployments; runtime detection catches the ones that got through.

- Alert on: `exec` into a pod, a privileged pod created, a new `cluster-admin` binding, a spike in secret reads, and a container reaching the metadata server.
- Audit contents depend on the matched audit rule. Metadata-level events omit request and response bodies. Keep audit events long enough for investigation and share only the fields needed for triage, such as actor, operation, resource, namespace, outcome and timestamp.
- Runtime sensors (Falco, Tetragon, GKE threat detection) catch process, file and network behaviour that admission cannot see. Tune them in the same way as any other alert: a rule nobody acts on is noise. See the [`detection-engineering`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/detection-engineering/SKILL.md) skill.

## Common mistakes

| Mistake | Why it matters |
| --- | --- |
| `privileged: true` "temporarily" | Full host access; it also disables most of the seccomp and capability controls you added |
| `hostPath` for a config file | The host filesystem, including other pods' projected tokens |
| `hostNetwork: true` for a metrics agent | Shares the node network namespace. NetworkPolicy behavior depends on the dataplane |
| A default service account with a bound token | One compromised pod can talk to the API as that account |
| `imagePullPolicy: Always` with a mutable tag | Two replicas of one Deployment can run different code |
| Admission policies with no owner | The first urgent deploy adds an exemption nobody removes |

## Next

- [Checks](https://github.com/greenblacked/security-toolbox/blob/main/checks/README.md) — the report scripts and their fixtures.
- [Policies](https://github.com/greenblacked/security-toolbox/blob/main/policies/README.md) — the pod security policy evaluated in CI.
- [Access Review](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/access-review/SKILL.md) — reviewing the RBAC and cloud IAM grants against usage.

## Hands-on lab

Practice with offline fixtures in the [Kubernetes workload review](/labs/kubernetes-workload/) lab.
