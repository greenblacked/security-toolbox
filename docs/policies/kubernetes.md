# Kubernetes pod security policy

The OPA / Conftest policy evaluates manifests for privileged containers, host namespaces and hostPath, privilege escalation, root settings and dangerous added capabilities. It warns about host ports and missing memory limits.

It runs on rendered manifests before deploy, which is the only point where a bad workload can be stopped cheaply. Once the pod is scheduled, the controls that matter are the cluster's own admission and the runtime sensor.

## Run

```bash
kustomize build overlays/prod | conftest test --policy policies/opa/kubernetes --namespace kubernetes.pod_security -
```

Render first: a `HelmRelease` or a `Kustomization` has no pod in it. `helm template`, `kustomize build` and `kubectl kustomize` all produce the manifests this policy reads.

Use Pod Security Admission for in-cluster enforcement. Review the [policy overview](/policies/#usage) and [Kubernetes workload check](/checks/kubernetes/) for complementary coverage.

## Rules

| Control | Level | Why | What satisfies it |
| --- | --- | --- | --- |
| `securityContext.privileged: true` | deny | Full access to the host's devices and kernel; it also cancels most of the other controls on this page | Remove it. There is no production workload that needs it; a node agent that does belongs in a privileged namespace with its own review |
| `hostPID`, `hostIPC`, `hostNetwork` | deny | The pod sees the host's processes, IPC or network namespace, which bypasses NetworkPolicy and per-pod isolation | Remove them. A CNI or metrics agent that needs `hostNetwork` runs in its own namespace, excluded deliberately |
| `hostPath` volume | deny | Mounts the node filesystem, including other pods' projected tokens and the kubelet directory | Use a `configMap`, `secret`, `emptyDir` or a CSI volume. A `hostPath` with `type: DirectoryOrCreate` is still a host mount |
| `allowPrivilegeEscalation` not `false` | deny | `setuid` binaries and file capabilities can raise privileges inside the container | `securityContext.allowPrivilegeEscalation: false` on every container |
| `runAsNonRoot` not `true` | deny | A root process inside the container is a root process on the host for most escape paths | `securityContext.runAsNonRoot: true`, and a numeric `runAsUser` so an image without a `USER` still passes |
| `runAsUser: 0` | deny | Explicit root, regardless of `runAsNonRoot` | Set a numeric non-zero UID; a container that must write needs `fsGroup` or an `emptyDir`, not root |
| Added capabilities | deny | `NET_ADMIN`, `SYS_ADMIN`, `SYS_PTRACE` and friends are the capabilities container escapes are built from | `capabilities: {drop: [ALL]}`, then add back only what is proven necessary |
| `hostPort` | warn | Binds a port on the node, bypassing Service-level access and NetworkPolicy, and limits scheduling to one pod per node per port | Use a Service, or an ingress controller that owns the port |
| No memory limit | warn | An unbounded pod can take the node down and evict its neighbours | `resources.limits.memory`; set requests too, or the scheduler cannot place it |

The container controls apply to `initContainers`, `containers` and `ephemeralContainers`. The pod-level `securityContext` is read for `runAsNonRoot` and `runAsUser` when the container does not set them, so a compliant pod can set them once.

## A manifest that passes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: app}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: web
          image: registry.example.com/web@sha256:...
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits: {cpu: 500m, memory: 256Mi}
```

The policy does not check `seccompProfile` or `readOnlyRootFilesystem`; the `restricted` Pod Security Standard does, and this manifest satisfies both.

## What it does not do

- **It is not the in-cluster enforcement.** A manifest that passes here can still be applied by someone with `kubectl`. Pod Security Admission on the namespace is the control that cannot be bypassed; this policy is the shift-left copy that catches it in review.
- **It says nothing about images.** Registry allow-lists and signature verification belong to the admission policy engine or Binary Authorization.
- **It does not read `NetworkPolicy`.** Default-deny is a separate object with its own review, and a missing one is not a pod-level finding.
- **It cannot see what a mutating webhook adds.** If a webhook injects a sidecar, the sidecar is not in the manifest this policy reads.

## Reading a finding

```
deny  apps/deployment/web: container "web" must set allowPrivilegeEscalation: false (CIS 5.2: minimise privilege escalation)
```

The prefix is the resource address (`kind/name`), then the container, then the control and its benchmark topic. The fix is in the container's `securityContext`, not in the pod's, because `allowPrivilegeEscalation` has no pod-level field.

Item numbers inside CIS 5.1 and 5.2 change between benchmark versions, so findings name the control topic rather than a number. Check the version you are audited against for the exact IDs.

[All policies](/policies/) · [Kubernetes guide](/kubernetes/) · [Workload check](/checks/kubernetes/)
