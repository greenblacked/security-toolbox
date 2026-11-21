# Kubernetes pod security policy

The OPA / Conftest policy evaluates manifests for privileged containers, host namespaces and hostPath, privilege escalation, root settings and dangerous added capabilities. It warns about host ports and missing memory limits.

## Run

```bash
kustomize build overlays/prod | conftest test --policy policies/opa/kubernetes --namespace kubernetes.pod_security -
```

Use Pod Security Admission for in-cluster enforcement. Review the [policy overview](/policies/#usage) and [Kubernetes workload check](/checks/kubernetes/) for complementary coverage.
