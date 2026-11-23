#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! -f "$1" || ! -r "$1" || -z "$2" ]]; then
  printf 'Usage: %s LAB_KUBECONFIG LAB_CONTEXT\n' "$0" >&2
  exit 2
fi

kubectl_lab=(kubectl --kubeconfig="$1" --context="$2" --request-timeout=15s)
server=$("${kubectl_lab[@]}" config view --minify -o 'jsonpath={.clusters[0].cluster.server}')
if [[ ! "$server" =~ ^https://127\.0\.0\.1:[0-9]+$ ]]; then
  printf 'Use a disposable cluster with an HTTPS API on 127.0.0.1.\n' >&2
  exit 2
fi

fixture_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/fixtures/pod-admission" && pwd)
namespace=$("${kubectl_lab[@]}" create -f - -o 'jsonpath={.metadata.name}' <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  generateName: toolbox-psa-
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.30
YAML
)
[[ "$namespace" == toolbox-psa-* ]]
cleanup() {
  local status=$?
  if ! "${kubectl_lab[@]}" delete namespace "$namespace" --wait=false >&2; then
    printf 'Cleanup failed. Remove the disposable namespace %s.\n' "$namespace" >&2
    return 1
  fi
  return "$status"
}
trap cleanup EXIT

namespaced=("${kubectl_lab[@]}" --namespace="$namespace")
"${namespaced[@]}" create serviceaccount toolbox-psa -o name
pod_request=("${namespaced[@]}" create --dry-run=server)
"${pod_request[@]}" -f "$fixture_dir/restricted.yaml" -o name
if denial=$("${pod_request[@]}" -f "$fixture_dir/missing-non-root.yaml" 2>&1); then
  printf 'FAIL: expected the Pod without runAsNonRoot to be denied.\n' >&2
  exit 1
fi
if [[ "$denial" != *'violates PodSecurity "restricted:v1.30"'* || "$denial" != *runAsNonRoot* ]]; then
  printf 'FAIL: expected a Pod Security Admission denial, got:\n%s\n' "$denial" >&2
  exit 1
fi
printf 'PASS: compliant Pod admitted and Pod without runAsNonRoot denied.\n'
