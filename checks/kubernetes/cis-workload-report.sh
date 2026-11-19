#!/usr/bin/env bash
# Read-only report on a few CIS Kubernetes Benchmark policy controls
# (section 5.1 RBAC and Service Accounts, section 5.2 Pod Security Standards).
#
#   checks/kubernetes/cis-workload-report.sh                 # live cluster via kubectl
#   checks/kubernetes/cis-workload-report.sh --pods pods.json --bindings crb.json
#
# Offline input is `kubectl get pods -A -o json` and
# `kubectl get clusterrolebindings -o json`. Item numbers inside 5.1 / 5.2
# differ between benchmark versions, so findings name the control topic.
# Exits 1 if any finding is reported. Needs jq (and kubectl for live mode).
set -Eeuo pipefail

pods_file='' bindings_file=''
while [ $# -gt 0 ]; do
  case "$1" in
    --pods) pods_file=${2:?}; shift 2 ;;
    --bindings) bindings_file=${2:?}; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$pods_file" ]; then pods=$(cat -- "$pods_file"); else pods=$(kubectl get pods -A -o json); fi
if [ -n "$bindings_file" ]; then crb=$(cat -- "$bindings_file"); else crb=$(kubectl get clusterrolebindings -o json); fi

# Namespaces whose pods are expected to need host access; findings there are skipped.
system_ns_re=${SYSTEM_NAMESPACES:-'^(kube-system|gke-managed-.*|gmp-system)$'}

findings=$(jq -r --arg sys "$system_ns_re" '
  # Container value, else pod value, else default. `//` would treat false as missing.
  def eff($sc; $psc; $k; $d): if $sc | has($k) then $sc[$k] elif $psc | has($k) then $psc[$k] else $d end;
  .items[]
  | select(.metadata.namespace | test($sys) | not)
  | . as $p
  | ($p.metadata.namespace + "/" + $p.metadata.name) as $id
  | ($p.spec.securityContext // {}) as $psc
  | (
      (if $p.spec.hostPID then "5.2 host namespaces\t\($id)\thostPID" else empty end),
      (if $p.spec.hostIPC then "5.2 host namespaces\t\($id)\thostIPC" else empty end),
      (if $p.spec.hostNetwork then "5.2 host namespaces\t\($id)\thostNetwork" else empty end),
      ($p.spec.volumes // [] | .[] | select(.hostPath) | "5.2 HostPath volumes\t\($id)\tvolume \(.name)"),
      (($p.spec.initContainers // []) + $p.spec.containers | .[]
        | (.securityContext // {}) as $sc
        | (
            (if $sc.privileged then "5.2 privileged containers\t\($id)\tcontainer \(.name)" else empty end),
            (if eff($sc; {}; "allowPrivilegeEscalation"; true) then "5.2 privilege escalation\t\($id)\tcontainer \(.name)" else empty end),
            (if (eff($sc; $psc; "runAsNonRoot"; false) | not) or (eff($sc; $psc; "runAsUser"; -1) == 0)
              then "5.2 root containers\t\($id)\tcontainer \(.name)" else empty end)
          ))
    )
' <<<"$pods")

admin=$(jq -r '
  .items[]
  | select(.roleRef.kind == "ClusterRole" and .roleRef.name == "cluster-admin")
  | select(.metadata.name | test("^system:") | not)
  | .metadata.name as $b
  | (.subjects // [])[]
  | "5.1 cluster-admin use\tclusterrolebinding/\($b)\t\(.kind) \(.namespace // "" | if . == "" then "" else . + "/" end)\(.name)"
' <<<"$crb")

all=$(printf '%s\n%s\n' "$findings" "$admin" | sed '/^$/d' | sort -u)
if [ -z "$all" ]; then
  echo "no findings"
  exit 0
fi
printf 'CONTROL\tOBJECT\tDETAIL\n%s\n' "$all" | awk -F'\t' '{ printf "%-28s %-40s %s\n", $1, $2, $3 }'
echo "findings: $(wc -l <<<"$all")"
exit 1
