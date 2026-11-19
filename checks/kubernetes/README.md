# Kubernetes CIS workload report

`cis-workload-report.sh` reports a subset of the CIS Kubernetes Benchmark policy controls that can be read from the API without node access:

| Benchmark section | Control topic | What is flagged |
| --- | --- | --- |
| 5.1 RBAC and Service Accounts | Limit use of the `cluster-admin` role | Non-`system:` ClusterRoleBindings to `cluster-admin`, with their subjects |
| 5.2 Pod Security Standards | Minimise privileged containers | `securityContext.privileged: true` |
| 5.2 | Minimise sharing of host PID / IPC / network namespaces | `hostPID`, `hostIPC`, `hostNetwork` |
| 5.2 | Minimise HostPath volumes | any `hostPath` volume |
| 5.2 | Minimise privilege escalation | `allowPrivilegeEscalation` not explicitly `false` |
| 5.2 | Minimise root containers | `runAsNonRoot` not `true`, or `runAsUser: 0` (container value overrides pod value) |

Item numbers inside 5.1 and 5.2 change between benchmark versions (and the GKE benchmark numbers its own sections differently), so findings name the section and the control topic. Check the benchmark version you are audited against for the exact IDs.

```bash
checks/kubernetes/cis-workload-report.sh                      # current kubectl context
kubectl get pods -A -o json > pods.json
kubectl get clusterrolebindings -o json > crb.json
checks/kubernetes/cis-workload-report.sh --pods pods.json --bindings crb.json
SYSTEM_NAMESPACES='^(kube-system|istio-system)$' checks/kubernetes/cis-workload-report.sh
```

Pods in `kube-system`, `gke-managed-*` and `gmp-system` are skipped by default because node agents legitimately need host access; override with `SYSTEM_NAMESPACES`.

Control-plane and node items (sections 1 to 4: API server flags, etcd, kubelet config, file permissions) need node access; use [kube-bench](https://github.com/aquasecurity/kube-bench) for those on self-managed clusters. On GKE the control plane is managed and Google publishes which items are the provider's responsibility.

The same pod controls are enforced pre-deploy by [`policies/opa/kubernetes`](../../policies/) and in-cluster by Pod Security Admission (`pod-security.kubernetes.io/enforce: restricted`).
