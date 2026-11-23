# Kubernetes CIS workload report

`cis-workload-report.sh` reports a subset of the CIS Kubernetes Benchmark policy controls that can be read from the API without node access:

| Benchmark section | Control topic | What is flagged |
| --- | --- | --- |
| 5.1 RBAC and Service Accounts | Limit use of the `cluster-admin` role | Subjects granted `cluster-admin` by any ClusterRoleBinding, except the built-in `system:masters` group |
| 5.2 Pod Security Standards | Minimise privileged containers | `securityContext.privileged: true` |
| 5.2 | Minimise sharing of host PID / IPC / network namespaces | `hostPID`, `hostIPC`, `hostNetwork` |
| 5.2 | Minimise HostPath volumes | any `hostPath` volume |
| 5.2 | Minimise privilege escalation | `allowPrivilegeEscalation` not explicitly `false` |
| 5.2 | Minimise root containers | `runAsNonRoot` not `true`, or `runAsUser: 0` (container value overrides pod value) |

The container controls apply to every entry in `initContainers`, `containers` and `ephemeralContainers`. `allowPrivilegeEscalation` is read from the container only, because the pod-level `securityContext` has no such field.

Input objects can be a Pod, or a workload whose pod template is read: Deployment, StatefulSet, DaemonSet, ReplicaSet and Job (`spec.template.spec`), and CronJob (`spec.jobTemplate.spec.template.spec`). Items without a `kind` are treated as Pods, since `kubectl get pods` output may omit it. Other kinds (for example ReplicationController or PodTemplate) are skipped in mixed lists. A nonempty export containing only unsupported kinds is invalid. The input can be a `List` (`.items`) or a single object. Live mode reads only Pods, which already includes the pods created by those controllers. Workload findings are labelled `namespace/kind/name`, for example `apps/deployment/web`. If an object has no `metadata.name`, its `generateName` is used; objects without a namespace are treated as `default`.

Item numbers inside 5.1 and 5.2 change between benchmark versions (and the GKE benchmark numbers its own sections differently), so findings name the section and the control topic. Check the benchmark version you are audited against for the exact IDs.

```bash
checks/kubernetes/cis-workload-report.sh                      # current kubectl context
kubectl get pods -A -o json > pods.json
kubectl get clusterrolebindings -o json > crb.json
checks/kubernetes/cis-workload-report.sh --pods pods.json --bindings crb.json
kubectl get deploy,sts,ds,rs,job,cronjob -A -o json > workloads.json   # templates, before pods exist
checks/kubernetes/cis-workload-report.sh --pods workloads.json --bindings crb.json
SYSTEM_NAMESPACES='^(kube-system|istio-system)$' checks/kubernetes/cis-workload-report.sh
```

Offline mode requires both files. Export both lists through `kubectl` and record the capture scope. A raw API page with a continuation token or remaining items is incomplete. An apparently final page alone does not establish coverage of earlier pages. Exit codes are 0 for complete inputs with no findings, 1 for findings, and 2 for invalid or unavailable inputs. On exit 2 the report emits an error without control results.

Objects in `kube-system`, `gke-managed-*` and `gmp-system` are skipped by default because node agents legitimately need host access; override with `SYSTEM_NAMESPACES`.

Control-plane and node items (sections 1 to 4: API server flags, etcd, kubelet config, file permissions) need node access; use [kube-bench](https://github.com/aquasecurity/kube-bench) for those on self-managed clusters. On GKE the control plane is managed and Google publishes which items are the provider's responsibility.

The same pod controls are enforced pre-deploy by [`policies/opa/kubernetes`](../../policies/) and in-cluster by Pod Security Admission (`pod-security.kubernetes.io/enforce: restricted`).
