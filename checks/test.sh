#!/usr/bin/env bash
# Run each check against its fixtures: good input must exit 0, bad input must exit 1.
set -Eeuo pipefail
cd "$(dirname "$0")"

output=$(mktemp)
trap 'rm -f -- "$output"' EXIT

fail=0
expect() { # expect <exit code> <description> <command...>
  local want=$1 what=$2 got=0; shift 2
  "$@" >"$output" 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok   - $what (exit $got)"
  else
    echo "FAIL - $what (wanted exit $want, got $got)"; cat "$output"; fail=1
  fi
}

expect 0 "gke good cluster" gke/gke-report.sh --file gke/fixtures/cluster-good.json
expect 1 "gke bad cluster" gke/gke-report.sh --file gke/fixtures/cluster-bad.json
gke_good=gke/fixtures/cluster-good.json
gke_report=gke/gke-report.sh

gke_case() { # gke_case <exit> <description> <jq fixture variant> <expected output pattern>
  local fixture
  fixture=$(jq "$3" "$gke_good")
  expect "$1" "$2" "$gke_report" --file /dev/stdin <<< "$fixture"
  if ! grep -Eq "$4" "$output"; then
    echo "FAIL - $2 (expected $4)"; cat "$output"; fail=1
  fi
}

gke_case 0 "gke accepts legacy Binary Authorization" '.binaryAuthorization = {enabled:true}' \
  '^PASS +Binary Authorization configured'
gke_case 0 "gke prefers explicitly disabled evaluation mode" \
  '.binaryAuthorization = {enabled:true,evaluationMode:"DISABLED"}' '^WARN +Binary Authorization configured'
gke_case 0 "gke requires the exact Binary Authorization mode" \
  '.binaryAuthorization.evaluationMode = "NOT_ENFORCED"' '^WARN +Binary Authorization configured'
gke_case 0 "gke IP networks N/A when modern IP access is disabled" \
  '.controlPlaneEndpointsConfig.ipEndpointsConfig = {enabled:false}' '^N/A +Control plane authorised networks'
gke_case 0 "gke modern authorised networks override legacy settings" \
  '.controlPlaneEndpointsConfig.ipEndpointsConfig = {enabled:true,authorizedNetworksConfig:{enabled:false}}' \
  '^WARN +Control plane authorised networks'
gke_case 0 "gke warns about an unrestricted CIDR" \
  '.masterAuthorizedNetworksConfig.cidrBlocks = [{cidrBlock:"0.0.0.0/0"},{cidrBlock:"::/0"}]' \
  '^WARN +Control plane authorised networks +an authorised CIDR allows all addresses'
gke_case 0 "gke distinguishes private endpoint enforcement" \
  '.controlPlaneEndpointsConfig.ipEndpointsConfig = {enabled:true,enablePublicEndpoint:false,authorizedNetworksConfig:{enabled:true}}' \
  '^WARN +Control plane authorised networks +private endpoint allowlist'
gke_case 0 "gke accepts configured private endpoint enforcement" \
  '.controlPlaneEndpointsConfig.ipEndpointsConfig = {enabled:true,enablePublicEndpoint:false,authorizedNetworksConfig:{enabled:true,privateEndpointEnforcementEnabled:true}}' \
  '^PASS +Control plane authorised networks'
gke_case 1 "gke honours explicit public pool override" \
  '.networkConfig.defaultEnablePrivateNodes = true | .nodePools[0].networkConfig.enablePrivateNodes = false' \
  '^FAIL +Private nodes'
gke_case 1 "gke honours explicit public cluster default" \
  '.networkConfig.defaultEnablePrivateNodes = false' '^FAIL +Private nodes'
gke_case 0 "gke Standard export may lack pools" 'del(.nodePools)' '^WARN +Private nodes'
gke_case 0 "gke Autopilot pool evidence may be unavailable" \
  'del(.nodePools) | .autopilot.enabled = true' '^WARN +Secure Boot on node pools +Autopilot'
gke_case 1 "gke detects certificate issuance without returned certificate data" \
  '.masterAuth.clientCertificateConfig.issueClientCertificate = true' '^FAIL +Static client certificate issuance'
gke_case 0 "gke cannot verify omitted issuance configuration" \
  'del(.masterAuth)' '^WARN +Static client certificate issuance'
gke_case 1 "gke requires a project in the Workload Identity pool" \
  '.workloadIdentityConfig.workloadPool = ".svc.id.goog"' '^FAIL +Workload Identity'
gke_case 0 "gke rejects an empty release channel as unconfigured" \
  '.releaseChannel.channel = ""' '^WARN +Release channel set'

for invalid_cluster in '' '{}' '{"error":{"code":403},"name":"x","location":"y"}' \
  '{"name":"x","location":"y","nodePools":[1]}' '{"name":"x","location":"y","legacyAbac":{"enabled":"false"}}' \
  '{"name":"x","location":"y"} {"name":"x","location":"y"}'; do
  expect 2 "gke rejects invalid cluster description" "$gke_report" --file /dev/stdin <<< "$invalid_cluster"
  if grep -qE '^(PASS|FAIL|WARN|failures:)' "$output"; then
    echo "FAIL - invalid GKE description emitted control results"; fail=1
  fi
done
expect 2 "gke rejects competing input modes" "$gke_report" --file "$gke_good" --cluster sample --location europe-west1

expect 0 "kubernetes good workloads" kubernetes/cis-workload-report.sh \
  --pods kubernetes/fixtures/pods-good.json --bindings kubernetes/fixtures/bindings-good.json
expect 1 "kubernetes bad workloads" kubernetes/cis-workload-report.sh \
  --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json
expect 0 "gcp good iam policy" gcp/iam-report.sh --file gcp/fixtures/policy-good.json --domain example.com
expect 1 "gcp bad iam policy" gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com

expect 0 "gcp empty direct policy" gcp/iam-report.sh --file /dev/stdin <<< '{"bindings":[]}'
expect 0 "gcp direct bindings omitted" gcp/iam-report.sh --file /dev/stdin <<< '{"etag":"fixture"}'
expect 2 "gcp file argument required" gcp/iam-report.sh --file
expect 2 "gcp rejects competing input modes" gcp/iam-report.sh --file /dev/stdin --project test
expect 2 "gcp rejects a raw NUL in JSON input" gcp/iam-report.sh --file /dev/stdin \
  < <(printf '{"bind\000ings":[]}\n')
invalid_policies=(
  '{}'
  '{"error":{"code":403},"bindings":[]}'
  '{"bindings":[{}]}'
  '{"bindings":null}'
  '{"bindings":[{"role":"roles/storage.objectViewer","members":[]}]}'
  '{"bindings":[]} {"bindings":[]}'
  '{"bindings":[],"version":2}'
  '{"bindings":[{"role":"roles/viewer","members":["user:test@example.com"],"condition":{"expression":"true"}}],"version":3}'
  '{"bindings":[{"role":"roles/storage.objectViewer_withcond_012abc","members":["user:test@example.com"]}],"version":1}'
  '{"bindings":[{"role":"projects/test/roles/reader_withcond_012abc","members":["user:test@example.com"]}],"version":1}'
  '{"bindings":[{"role":"roles/owner","members":["user:test@example.com"],"condition":{"expression":"true"}}],"version":3}'
)
for invalid_policy in "${invalid_policies[@]}"; do
  expect 2 "gcp rejects invalid export" gcp/iam-report.sh --file /dev/stdin <<< "$invalid_policy"
  if grep -qE '^(PASS|failures:)' "$output"; then
    echo "FAIL - invalid IAM policy produced control results"
    fail=1
  fi
done

# A partial offline invocation must never attempt to read the current cluster.
(
  stub=$(mktemp -d)
  trap 'rm -rf -- "$stub"' EXIT
  cat >"$stub/kubectl" <<'SH'
#!/usr/bin/env bash
touch "${STUB_CALLS:?}"
printf '{"items":[]}\n'
exit "${STUB_EXIT:-0}"
SH
  chmod +x "$stub/kubectl"
  export PATH="$stub:$PATH" STUB_CALLS="$stub/calls"
  report=kubernetes/cis-workload-report.sh
  expect 2 "kubernetes requires bindings in offline mode" "$report" --pods /dev/null
  expect 2 "kubernetes requires workloads in offline mode" "$report" --bindings /dev/null
  expect 2 "kubernetes requires a file argument" "$report" --pods
  expect 0 "kubernetes rejects offline inputs before live lookup" test ! -e "$STUB_CALLS"
  expect 0 "kubernetes accepts valid empty live lists" "$report"
  expect 2 "kubernetes rejects a failed live read" env STUB_EXIT=1 "$report"

  printf '{"kind":"ClusterRoleBindingList","items":[]}\n' >"$stub/empty-bindings"
  expect 0 "kubernetes accepts valid empty offline lists" "$report" \
    --pods /dev/stdin --bindings "$stub/empty-bindings" <<< '{"kind":"PodList","items":[]}'
  invalid_workloads=(
    ''
    '{'
    '{"kind":"Status","status":"Failure"}'
    '{"kind":"ServiceList","items":[]}'
    '{"kind":"PodList","items":[],"metadata":{"continue":"next"}}'
    '{"items":[],"metadata":{"remainingItemCount":1}}'
    '{"items":[]} {"items":[]}'
    '{"items":[{"kind":"Pod","spec":{}}]}'
    '{"items":[{"kind":"Service"}]}'
    '{"spec":{"containers":[{"name":"app","securityContext":{"allowPrivilegeEscalation":"false"}}]}}'
  )
  for invalid_workload in "${invalid_workloads[@]}"; do
    expect 2 "kubernetes rejects invalid or incomplete workloads" "$report" \
      --pods /dev/stdin --bindings "$stub/empty-bindings" <<< "$invalid_workload"
    if [ "$(wc -l <"$output")" -ne 1 ] || ! grep -q '^Kubernetes report input error:' "$output"; then
      echo "FAIL - invalid workloads emitted unexpected output"; fail=1
    fi
  done
  expect 2 "kubernetes rejects incomplete bindings" "$report" \
    --pods kubernetes/fixtures/pods-good.json --bindings /dev/stdin \
    <<< '{"items":[],"metadata":{"remainingItemCount":1}}'
  expect 2 "kubernetes rejects missing roleRef" "$report" \
    --pods kubernetes/fixtures/pods-bad.json --bindings /dev/stdin \
    <<< '{"items":[{"metadata":{"name":"admin"}}]}'
  if [ "$(wc -l <"$output")" -ne 1 ] || ! grep -q '^Kubernetes report input error:' "$output"; then
    echo "FAIL - invalid bindings emitted unexpected output"; fail=1
  fi
  expect 2 "kubernetes rejects an invalid namespace regex with empty input" env SYSTEM_NAMESPACES='[' \
    "$report" --pods /dev/stdin --bindings "$stub/empty-bindings" <<< '{"items":[]}'
  exit "$fail"
) || fail=1

# The bad fixtures must trip every control they were written for.
expect 0 "gke bad trips 9 failures" bash -c \
  'gke/gke-report.sh --file gke/fixtures/cluster-bad.json | grep -qx "failures: 9"'
expect 0 "kubernetes bad trips 14 findings" bash -c \
  'kubernetes/cis-workload-report.sh --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json | grep -qx "findings: 14"'
expect 0 "gcp bad trips 3 failures" bash -c \
  'gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com | grep -qx "failures: 3"'
expect 0 "gcp bad reports an outside domain" bash -c \
  'gcp/iam-report.sh --file gcp/fixtures/policy-bad.json --domain example.com | grep -q "from another domain"'
# Ephemeral containers and workload wrappers (Deployment, CronJob) are walked too.
# shellcheck disable=SC2016 # $1 expands inside the bash -c script
for want in 'privileged containers +default/debug +container debugger' \
  'privileged containers +apps/deployment/web +container app' \
  'host namespaces +apps/cronjob/backup +hostIPC'; do
  expect 0 "kubernetes bad reports: $want" bash -c \
    'kubernetes/cis-workload-report.sh --pods kubernetes/fixtures/pods-bad.json --bindings kubernetes/fixtures/bindings-bad.json | grep -Eq "$1"' _ "$want"
done

exit "$fail"
