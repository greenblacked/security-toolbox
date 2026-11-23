# Verify Kubernetes Pod Security Admission

Verify that Kubernetes admits a restricted Pod and rejects a Pod missing an explicit non-root requirement. Allow 25 minutes once the cluster is ready. Use Bash, kubectl, a disposable local Kubernetes cluster running v1.30 or later, and the [lab kit](/labs/#get-the-lab-kit). The example uses kind and its container runtime.

## Create a temporary cluster and test admission

From the extracted kit, run:

```bash
(
  set -eu
  lab_dir=$(mktemp -d)
  cluster="toolbox-psa-${lab_dir##*.}"
  cluster=$(printf '%s' "$cluster" | tr '[:upper:]' '[:lower:]')
  cleanup() {
    kind delete cluster --name "$cluster" || return 1
    rm -rf -- "$lab_dir"
  }
  trap cleanup EXIT
  kind create cluster --name "$cluster" --kubeconfig "$lab_dir/kubeconfig"
  bash labs/pod-admission.sh "$lab_dir/kubeconfig" "kind-$cluster"
)
```

The helper creates a uniquely named namespace with `restricted:v1.30` in enforce mode. It submits both Pod manifests using server-side dry runs. Kubernetes evaluates admission without saving or starting the Pods. The helper requests namespace deletion on exit. The outer command deletes the disposable cluster. If cluster cleanup fails, retry the deletion with the cluster name printed by kind.

## Read the result

Expect the compliant Pod to be accepted and the other Pod to receive a Pod Security Admission denial for `runAsNonRoot`. The helper treats generic failures, such as connectivity or authorization errors, as failed exercises. Compare the two supplied manifests to see which field changes the result.

Use a Pod when testing this enforcement. Deployments can pass admission at creation and still fail to create Pods when their templates violate the policy. For a real rollout, assess existing workloads in warn or audit mode and choose a policy version deliberately before enabling enforcement.

Related reading: [Kubernetes Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) and [Kubernetes workload review](/labs/kubernetes-workload/).
