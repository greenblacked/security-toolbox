#!/usr/bin/env bash
# Read-only GKE cluster hardening report.
#
#   checks/gke/gke-report.sh --cluster NAME --location REGION_OR_ZONE [--project ID]
#   checks/gke/gke-report.sh --file cluster.json   # output of `gcloud container clusters describe --format=json`
#
# Exits 0 if no control fails, 1 for failed controls, or 2 for invalid or unavailable input.
# Needs jq; needs gcloud with container.clusters.get unless --file is used.
set -Eeuo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

input_error() {
  printf 'GKE report input error: %s\n' "$1" >&2
  exit 2
}

file='' cluster='' location='' project=''
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ -n "${2-}" ] && [ -z "$file" ] || input_error "--file requires one value"; file=$2; shift 2 ;;
    --cluster) [ -n "${2-}" ] && [ -z "$cluster" ] || input_error "--cluster requires one value"; cluster=$2; shift 2 ;;
    --location) [ -n "${2-}" ] && [ -z "$location" ] || input_error "--location requires one value"; location=$2; shift 2 ;;
    --project) [ -n "${2-}" ] && [ -z "$project" ] || input_error "--project requires one value"; project=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

command -v jq >/dev/null || input_error "jq is required"
if [ -n "$file" ]; then
  if [ -n "$cluster$location$project" ]; then
    input_error "use either --file or --cluster and --location"
  fi
  document=$(jq -c . -- "$file" 2>/dev/null) || input_error "could not read the cluster export"
elif [ -n "$cluster" ] && [ -n "$location" ]; then
  args=(container clusters describe "$cluster" --location "$location" --format=json)
  [ -n "$project" ] && args+=(--project "$project")
  document=$(gcloud "${args[@]}" | jq -c . 2>/dev/null) || input_error "could not fetch the cluster"
else
  usage
fi

# Validate fields consumed by the report. The API can omit optional fields.
json=$(jq -ces '
  def optional($path; $expected): getpath($path) | . == null or type == $expected;
  def nonblank: type == "string" and test("\\S");
  def networks:
    optional(["enabled"]; "boolean") and optional(["privateEndpointEnforcementEnabled"]; "boolean")
    and optional(["gcpPublicCidrsAccessEnabled"]; "boolean")
    and (.cidrBlocks == null or (.cidrBlocks | type == "array" and
      all(.[]; type == "object" and (.cidrBlock | type == "string" and test("^[0-9a-fA-F:.]+/[0-9]+$")))));
  def pool:
    type == "object" and optional(["config"]; "object") and optional(["management"]; "object")
    and optional(["networkConfig"]; "object")
    and optional(["config","workloadMetadataConfig"]; "object")
    and optional(["config","shieldedInstanceConfig"]; "object")
    and optional(["config","serviceAccount"]; "string")
    and optional(["config","workloadMetadataConfig","mode"]; "string")
    and optional(["config","shieldedInstanceConfig","enableSecureBoot"]; "boolean")
    and optional(["config","shieldedInstanceConfig","enableIntegrityMonitoring"]; "boolean")
    and optional(["management","autoUpgrade"]; "boolean")
    and optional(["networkConfig","enablePrivateNodes"]; "boolean");
  if length != 1 then error("expected one object") else .[0] end
  | . as $cluster
  | if type == "object" and (has("error") | not) and (.name | nonblank) and (.location | nonblank)
    and all(["autopilot","workloadIdentityConfig","shieldedNodes","binaryAuthorization","networkConfig",
      "networkPolicy","privateClusterConfig","masterAuthorizedNetworksConfig","legacyAbac","masterAuth",
      "releaseChannel","controlPlaneEndpointsConfig"][]; . as $key | $cluster | optional([$key]; "object"))
    then . else error("invalid cluster description") end
  | if optional(["controlPlaneEndpointsConfig","ipEndpointsConfig"]; "object")
    and optional(["controlPlaneEndpointsConfig","ipEndpointsConfig","authorizedNetworksConfig"]; "object")
    and optional(["masterAuth","clientCertificateConfig"]; "object")
    and optional(["autopilot","enabled"]; "boolean")
    and optional(["workloadIdentityConfig","workloadPool"]; "string")
    and optional(["shieldedNodes","enabled"]; "boolean")
    and optional(["binaryAuthorization","enabled"]; "boolean")
    and optional(["binaryAuthorization","evaluationMode"]; "string")
    and optional(["networkConfig","datapathProvider"]; "string")
    and optional(["networkConfig","defaultEnablePrivateNodes"]; "boolean")
    and optional(["networkPolicy","enabled"]; "boolean")
    and optional(["privateClusterConfig","enablePrivateNodes"]; "boolean")
    and optional(["privateClusterConfig","enablePrivateEndpoint"]; "boolean")
    and optional(["controlPlaneEndpointsConfig","ipEndpointsConfig","enabled"]; "boolean")
    and optional(["controlPlaneEndpointsConfig","ipEndpointsConfig","enablePublicEndpoint"]; "boolean")
    and (.controlPlaneEndpointsConfig.ipEndpointsConfig.authorizedNetworksConfig | networks)
    and (.masterAuthorizedNetworksConfig | networks)
    and optional(["legacyAbac","enabled"]; "boolean")
    and optional(["masterAuth","clientCertificateConfig","issueClientCertificate"]; "boolean")
    and optional(["masterAuth","clientCertificate"]; "string") and optional(["masterAuth","clientKey"]; "string")
    and optional(["releaseChannel","channel"]; "string")
    and (.nodePools == null or (.nodePools | type == "array" and all(.[]; pool)))
    then . else error("invalid control fields") end
  | .masterAuth |= (if . == null then null else
      .clientCertificatePresent = ((.clientCertificate // "") != "")
      | .clientKeyPresent = ((.clientKey // "") != "")
      | del(.clientCertificate, .clientKey, .password, .username) end)
' 2>/dev/null <<<"$document") || input_error "expected one GKE cluster description with valid control fields"
unset document

fails=0
report() { # report <PASS|FAIL|WARN> <control> <detail>
  printf '%-4s  %-38s %s\n' "$1" "$2" "$3"
  if [ "$1" = FAIL ]; then fails=$((fails + 1)); fi
}
q() { jq -r "$1" <<<"$json"; }
check() { # check <control> <jq boolean expr> <fail detail> [WARN]
  local level=${4:-FAIL}
  local result
  result=$(q "$2") || input_error "could not evaluate $1"
  if [ "$result" = true ]; then report PASS "$1" ""; else report "$level" "$1" "$3"; fi
}

pool_count=$(q '(.nodePools // []) | length')
pool_evidence="no node pools in the export"
if [ "$(q '.autopilot.enabled == true')" = true ]; then
  pool_evidence="Autopilot node-pool configuration is unavailable in this export"
fi
check_pools() {
  if [ "$pool_count" -eq 0 ]; then
    report WARN "$1" "$pool_evidence"
  else
    check "$@"
  fi
}

echo "cluster: $(q '.name // "unknown"')  location: $(q '.location // "unknown"')"

check "Workload Identity" '(.workloadIdentityConfig.workloadPool // "") | test("^[a-z][a-z0-9-]{4,28}[a-z0-9]\\.svc\\.id\\.goog$")' \
  "enable with --workload-pool=PROJECT_ID.svc.id.goog"
check_pools "Node pools use GKE metadata server" \
  '[.nodePools[]? | .config.workloadMetadataConfig.mode == "GKE_METADATA"] | (length > 0 and all)' \
  "set --workload-metadata=GKE_METADATA on every node pool"
check "Shielded GKE Nodes" '.shieldedNodes.enabled == true' "enable with --enable-shielded-nodes"
check_pools "Secure Boot on node pools" \
  '[.nodePools[]? | .config.shieldedInstanceConfig.enableSecureBoot == true] | (length > 0 and all)' \
  "create node pools with --shielded-secure-boot" WARN
check_pools "Integrity monitoring on node pools" \
  '[.nodePools[]? | .config.shieldedInstanceConfig.enableIntegrityMonitoring == true] | (length > 0 and all)' \
  "create node pools with --shielded-integrity-monitoring"
# shellcheck disable=SC2016 # Variable references are evaluated by jq.
check "Binary Authorization configured" '
  .binaryAuthorization | .evaluationMode as $mode
  | if $mode == null or $mode == "EVALUATION_MODE_UNSPECIFIED"
    then .enabled == true else $mode == "PROJECT_SINGLETON_POLICY_ENFORCE" end' \
  "configure PROJECT_SINGLETON_POLICY_ENFORCE and verify the project policy separately" WARN
check "NetworkPolicy configured" \
  '.networkConfig.datapathProvider == "ADVANCED_DATAPATH" or .networkPolicy.enabled == true' \
  "use GKE Dataplane V2 (--enable-dataplane-v2) or enable network policy"

# shellcheck disable=SC2016 # Variable references are evaluated by jq.
private_nodes=$(q '
  def prefer($modern; $legacy): if $modern == null then $legacy else $modern end;
  prefer(.networkConfig.defaultEnablePrivateNodes; .privateClusterConfig.enablePrivateNodes) as $default
  | [.nodePools[]? | prefer(.networkConfig.enablePrivateNodes; $default)] as $pools
  | if ($pools | length) == 0 then "unknown"
    elif any($pools[]; . == false) then "public"
    elif all($pools[]; . == true) then "private" else "unknown" end')
case "$private_nodes" in
  private) report PASS "Private nodes" "private nodes configured on all listed pools" ;;
  public) report FAIL "Private nodes" "a listed pool allows public nodes; use --enable-private-nodes" ;;
  unknown) report WARN "Private nodes" "private-node coverage is unavailable for one or more pools" ;;
esac

# shellcheck disable=SC2016 # Variable references are evaluated by jq.
network_status=$(q '
  .controlPlaneEndpointsConfig.ipEndpointsConfig as $ip
  | ($ip.authorizedNetworksConfig // .masterAuthorizedNetworksConfig) as $networks
  | if $ip.enabled == false then "not-applicable"
    elif $networks.enabled != true then "unverified"
    elif any($networks.cidrBlocks[]?; .cidrBlock | test("/0+$")) then "unrestricted"
    elif $networks.gcpPublicCidrsAccessEnabled == true then "google-public"
    elif ((if $ip.enablePublicEndpoint == null then .privateClusterConfig.enablePrivateEndpoint == true
           else $ip.enablePublicEndpoint == false end) and $networks.privateEndpointEnforcementEnabled != true)
    then "private-unverified"
    else "configured" end')
case "$network_status" in
  not-applicable) report N/A "Control plane authorised networks" "direct IP access is disabled; verify DNS endpoint access separately" ;;
  configured) report PASS "Control plane authorised networks" "IP allowlist configured" ;;
  unrestricted) report WARN "Control plane authorised networks" "an authorised CIDR allows all addresses" ;;
  google-public) report WARN "Control plane authorised networks" "Google Cloud public CIDR access is enabled" ;;
  private-unverified) report WARN "Control plane authorised networks" "private endpoint allowlist enforcement is unverified" ;;
  unverified) report WARN "Control plane authorised networks" "enable and verify the IP endpoint allowlist" ;;
esac

check "Legacy ABAC disabled" '(.legacyAbac.enabled // false) == false' "disable with --no-enable-legacy-authorization"
certificate_status=$(q '
  .masterAuth
  | if .clientCertificatePresent or .clientKeyPresent or .clientCertificateConfig.issueClientCertificate == true
    then "enabled" elif .clientCertificateConfig.issueClientCertificate == false
    then "disabled" else "unknown" end')
case "$certificate_status" in
  enabled) report FAIL "Static client certificate issuance" "stop issuing static client certificates and rotate existing credentials" ;;
  disabled) report PASS "Static client certificate issuance" "issuance disabled in the export" ;;
  unknown) report WARN "Static client certificate issuance" "issuance setting is unavailable in the export" ;;
esac

check_pools "Custom node service account configured" \
  '[.nodePools[]? | ((.config.serviceAccount // "") | length > 0 and . != "default") and ((.config.serviceAccount // "") | test("^[0-9]+-compute@developer\\.gserviceaccount\\.com$") | not)] | (length > 0 and all)' \
  "use a dedicated least-privilege node service account"
check "Release channel set" '.releaseChannel.channel | IN("RAPID", "REGULAR", "STABLE", "EXTENDED")' \
  "enrol in a release channel (REGULAR or STABLE)" WARN
check_pools "Node auto-upgrade" '[.nodePools[]? | .management.autoUpgrade == true] | (length > 0 and all)' \
  "enable auto-upgrade on every node pool" WARN

echo "failures: $fails"
[ "$fails" -eq 0 ]
