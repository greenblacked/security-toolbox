# Kubernetes workload review

Use two local workload and RBAC fixture pairs to identify policy findings. Allow 40 minutes. Install Bash and jq.

## Exercise

Run the fixture-only wrapper from the [extracted lab kit directory](/labs/#get-the-lab-kit). Each invocation requires both file paths.

```bash
(
  set -eu
  labs/kubernetes-workload.sh \
    checks/kubernetes/fixtures/pods-good.json checks/kubernetes/fixtures/bindings-good.json
  status=0
  labs/kubernetes-workload.sh \
    checks/kubernetes/fixtures/pods-bad.json checks/kubernetes/fixtures/bindings-bad.json || status=$?
  test "$status" -eq 1
)
```

## Verify and clean up

The good pair exits 0 and reports zero findings. The bad pair exits 1 and reports 14 findings. Missing or unreadable inputs exit 2 before the report runs. Select one Pod and one binding finding, name the owner, and explain what you would change or record as a time-limited exception. Use the resource and finding text as evidence. The wrapper deletes its empty temporary home when it exits.

Related reading: [Kubernetes workload check](/checks/kubernetes/) and [Kubernetes pod security policy](/policies/kubernetes/).

Continue with [Verify Kubernetes Pod Security Admission](/labs/pod-security-admission/) to see how the API server handles a Pod.
