#!/usr/bin/env bash
# Read-only GKE cluster hardening report.
#
#   checks/gke/gke-report.sh --cluster NAME --location REGION_OR_ZONE [--project ID]
#   checks/gke/gke-report.sh --file cluster.json   # output of `gcloud container clusters describe --format=json`
#
# Prints PASS / FAIL / WARN per control. Exits 1 if any FAIL, 0 otherwise.
# Needs jq; needs gcloud with container.clusters.get unless --file is used.
set -Eeuo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

file='' cluster='' location='' project=''
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file=${2:?}; shift 2 ;;
    --cluster) cluster=${2:?}; shift 2 ;;
    --location) location=${2:?}; shift 2 ;;
    --project) project=${2:?}; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

if [ -n "$file" ]; then
  json=$(cat -- "$file")
elif [ -n "$cluster" ] && [ -n "$location" ]; then
  args=(container clusters describe "$cluster" --location "$location" --format=json)
  [ -n "$project" ] && args+=(--project "$project")
  json=$(gcloud "${args[@]}")
else
  usage
fi

fails=0
report() { # report <PASS|FAIL|WARN> <control> <detail>
  printf '%-4s  %-38s %s\n' "$1" "$2" "$3"
  if [ "$1" = FAIL ]; then fails=$((fails + 1)); fi
}
q() { jq -r "$1" <<<"$json"; }
check() { # check <control> <jq boolean expr> <fail detail> [WARN]
  local level=${4:-FAIL}
  if [ "$(q "$2")" = true ]; then report PASS "$1" ""; else report "$level" "$1" "$3"; fi
}

echo "cluster: $(q '.name // "unknown"')  location: $(q '.location // "unknown"')"

check "Workload Identity" '(.workloadIdentityConfig.workloadPool // "") | endswith(".svc.id.goog")' \
  "enable with --workload-pool=PROJECT_ID.svc.id.goog"
check "Node pools use GKE metadata server" \
  '[.nodePools[]? | .config.workloadMetadataConfig.mode == "GKE_METADATA"] | (length > 0 and all)' \
  "set --workload-metadata=GKE_METADATA on every node pool"
check "Shielded GKE Nodes" '.shieldedNodes.enabled == true' "enable with --enable-shielded-nodes"
check "Secure Boot on node pools" \
  '[.nodePools[]? | .config.shieldedInstanceConfig.enableSecureBoot == true] | (length > 0 and all)' \
  "create node pools with --shielded-secure-boot" WARN
check "Integrity monitoring on node pools" \
  '[.nodePools[]? | .config.shieldedInstanceConfig.enableIntegrityMonitoring == true] | (length > 0 and all)' \
  "create node pools with --shielded-integrity-monitoring"
check "Binary Authorization enforced" \
  '(.binaryAuthorization.evaluationMode // "DISABLED") | test("ENFORCE")' \
  "set --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE and define a policy" WARN
check "NetworkPolicy enforcement" \
  '.networkConfig.datapathProvider == "ADVANCED_DATAPATH" or .networkPolicy.enabled == true' \
  "use GKE Dataplane V2 (--enable-dataplane-v2) or enable network policy"
check "Private nodes" '.privateClusterConfig.enablePrivateNodes == true' \
  "nodes have public IPs; use --enable-private-nodes"
check "Control plane authorised networks" '.masterAuthorizedNetworksConfig.enabled == true' \
  "restrict control plane access with --enable-master-authorized-networks" WARN
check "Legacy ABAC disabled" '(.legacyAbac.enabled // false) == false' "disable with --no-enable-legacy-authorization"
check "No client certificate issued" '(.masterAuth.clientKey // "") == ""' \
  "cluster issued a static client certificate; rotate credentials and stop issuing it"
check "Node SA is not the default compute SA" \
  '[.nodePools[]? | (.config.serviceAccount // "default") != "default" and ((.config.serviceAccount // "") | test("-compute@developer") | not)] | (length > 0 and all)' \
  "use a dedicated least-privilege node service account"
check "Release channel set" '(.releaseChannel.channel // "UNSPECIFIED") != "UNSPECIFIED"' \
  "enrol in a release channel (REGULAR or STABLE)" WARN
check "Node auto-upgrade" '[.nodePools[]? | .management.autoUpgrade == true] | (length > 0 and all)' \
  "enable auto-upgrade on every node pool" WARN

echo "failures: $fails"
[ "$fails" -eq 0 ]
