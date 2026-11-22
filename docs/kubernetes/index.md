# Kubernetes / GKE

**Who this is for:** platform engineers who run GKE clusters and the teams deploying to them. You should be comfortable with `kubectl`, RBAC objects and a pod spec.

Report first. Everything here is checkable read-only before you change anything:
[`checks/gke/gke-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/gke-report.sh) covers the cluster and
[`checks/kubernetes/cis-workload-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/kubernetes/cis-workload-report.sh)
covers workloads. Both run against live state or a saved export.

## Cluster (GKE)

[`checks/gke/gke-report.sh`](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/gke-report.sh) reports the cluster-level controls from `gcloud container clusters describe`; the [checklist](https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/README.md) explains each one.

- **Workload Identity Federation for GKE** on the cluster and `GKE_METADATA` on every node pool, so pods never see the node service account.
- **Shielded GKE Nodes** with integrity monitoring (and Secure Boot where drivers allow).
- **Private nodes**, control-plane authorised networks, no legacy ABAC, no static client certificate.
- **Dedicated node service account** with `roles/container.defaultNodeServiceAccount` only.
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
- Control-plane audit logs are separate from workload logs. Enable `ADMIN_READ`, `DATA_READ`, `DATA_WRITE` and `POLICY_WRITE` on `auditConfigs` for `k8s.io`, and send them to a log sink in another project. Without `ADMIN_READ` you cannot answer "who deleted that deployment".

### Node pools

Split pools by trust and by change rate, not by convenience. A pool that runs untrusted batch work should not share a kernel, a node identity or an eviction budget with the ingress controllers.

- `image_type = "COS_CONTAINERD"` — the minimal, signed node image. Docker-based images are gone on current versions.
- **GKE Sandbox** (`sandbox_type = "gvisor"`) for multi-tenant or untrusted workloads: a user-space kernel between the container and the host.
- `auto_repair` and `auto_upgrade` on; surge settings that keep capacity during a rolling upgrade.
- Taints and tolerations so a workload lands only on the pool built for it, and `nodeSelector`/affinity so it does not drift.
- One node service account per pool where the pools have different cloud permissions. The node identity is reachable by anything that can run a pod on that node unless Workload Identity is on.

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

A compliant container sets `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`, and ideally `readOnlyRootFilesystem: true`, plus resource requests and limits.

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
- `automountServiceAccountToken: false` is the default for pods that never call the API, and it removes a credential from the container for free.
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
| `create` on `daemonsets` or `nodes/proxy` | Node-level reach |
| `patch` on `validatingwebhookconfigurations` | Disable your own admission controls |

- No `cluster-admin` bindings outside break-glass groups; CI deployers get namespace-scoped Roles.
- Avoid wildcard verbs/resources and `escalate`, `bind`, `impersonate` grants; treat `create pods` and `get secrets` as privileged.
- `automountServiceAccountToken: false` on pods that do not call the API.
- On GKE, map Google Groups to RBAC (Google Groups for RBAC) instead of binding individual users.
- Bind to groups, and keep the group membership in the identity provider where it is audited and reviewed. A RoleBinding to a user is invisible to an access review that reads the IdP.
- Prefer `RoleBinding` in the namespace over `ClusterRoleBinding`; a ClusterRole can still be bound namespace-scoped.
- Bound service-account tokens carry an audience. Use `TokenRequest` with a specific audience rather than the legacy auto-mounted token, and set `expirationSeconds` to what the workload actually needs.

```bash
# Who can do what, for one identity
kubectl auth can-i --list --as=system:serviceaccount:app:deployer -n app
# Everyone holding cluster-admin
kubectl get clusterrolebindings -o json \
  | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .subjects[]? | "\(.kind)/\(.namespace // "-")/\(.name)"'
# Service accounts with a legacy auto-mounted token in use
kubectl get pods -A -o json \
  | jq -r '.items[] | select(.spec.automountServiceAccountToken != false) | "\(.metadata.namespace)/\(.metadata.name)"'
```

## Network

Start every namespace with default-deny ingress and egress, then allow DNS and the specific flows each workload needs. A NetworkPolicy without an enforcing dataplane does nothing, so verify enforcement first.

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
metadata: {name: allow-dns-and-api, namespace: app}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
```

- Default-deny egress breaks DNS first. Allow `kube-system` on 53 before you enforce, or every lookup starts failing at once.
- The metadata server is `169.254.169.254`. With Workload Identity the node identity is not exposed to pods, but blocking the link-local range on egress is a cheap second layer.
- Ingress controllers and metrics scrapers need explicit allows; a namespace that only denies will lose health checks and look healthy while failing.
- NetworkPolicy is additive and namespaced; a cluster-wide default needs the same policy in every namespace, which is a job for the policy engine or a GitOps template.

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
- Kubernetes audit logs carry the request body for creates and patches. Send them somewhere with retention longer than your incident window, because the pod that caused the incident is usually gone.
- Runtime sensors (Falco, Tetragon, GKE threat detection) catch process, file and network behaviour that admission cannot see. Tune them in the same way as any other alert: a rule nobody acts on is noise. See the [`detection-engineering`](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/detection-engineering/SKILL.md) skill.

## Common mistakes

| Mistake | Why it matters |
| --- | --- |
| `privileged: true` "temporarily" | Full host access; it also disables most of the seccomp and capability controls you added |
| `hostPath` for a config file | The host filesystem, including other pods' projected tokens |
| `hostNetwork: true` for a metrics agent | Bypasses NetworkPolicy and exposes every host port |
| A default service account with a bound token | One compromised pod can talk to the API as that account |
| `imagePullPolicy: Always` with a mutable tag | Two replicas of one Deployment can run different code |
| Admission policies with no owner | The first urgent deploy adds an exemption nobody removes |

## Next

- [Checks](https://github.com/greenblacked/security-toolbox/blob/main/checks/README.md) — the report scripts and their fixtures.
- [Policies](https://github.com/greenblacked/security-toolbox/blob/main/policies/README.md) — the pod security policy evaluated in CI.
- [Access Review](https://github.com/greenblacked/security-toolbox/blob/main/plugins/security/skills/access-review/SKILL.md) — reviewing the RBAC and cloud IAM grants against usage.
