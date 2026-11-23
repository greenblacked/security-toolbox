#!/usr/bin/env bash
# Read-only report on a few CIS Kubernetes Benchmark policy controls
# (section 5.1 RBAC and Service Accounts, section 5.2 Pod Security Standards).
#
#   checks/kubernetes/cis-workload-report.sh                 # live cluster via kubectl
#   checks/kubernetes/cis-workload-report.sh --pods pods.json --bindings crb.json
#
# Offline input is `kubectl get pods -A -o json` (or a List / single object of
# Pod, Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob) and
# `kubectl get clusterrolebindings -o json`. Item numbers inside 5.1 / 5.2
# differ between benchmark versions, so findings name the control topic.
# Exits 0 for no findings, 1 for findings, or 2 for unavailable or invalid input.
# Needs jq (and kubectl for live mode).
set -Eeuo pipefail

input_error() {
  printf 'Kubernetes report input error: %s\n' "$1" >&2
  exit 2
}

pods_file='' bindings_file=''
while [ $# -gt 0 ]; do
  case "$1" in
    --pods) [ -z "$pods_file" ] && [ -n "${2-}" ] || input_error "--pods requires one file"; pods_file=$2; shift 2 ;;
    --bindings) [ -z "$bindings_file" ] && [ -n "${2-}" ] || input_error "--bindings requires one file"; bindings_file=$2; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if { [ -n "$pods_file" ] && [ -z "$bindings_file" ]; } ||
   { [ -z "$pods_file" ] && [ -n "$bindings_file" ]; }; then
  input_error "provide --pods and --bindings together for offline mode"
fi
command -v jq >/dev/null || input_error "jq is required"
if [ -n "$pods_file" ]; then
  pods=$(jq -c . -- "$pods_file" 2>/dev/null) || input_error "could not read the workload export"
  crb=$(jq -c . -- "$bindings_file" 2>/dev/null) || input_error "could not read the binding export"
else
  pods=$(kubectl get pods -A -o json | jq -c . 2>/dev/null) ||
    input_error "could not fetch pods"
  crb=$(kubectl get clusterrolebindings -o json | jq -c . 2>/dev/null) ||
    input_error "could not fetch cluster role bindings"
fi

# List metadata can be omitted by clients. A raw list with continuation evidence is incomplete.
list_validation='
  def optional($key; $expected): .[$key] | . == null or type == $expected;
  def nonblank: type == "string" and test("\\S");
  def one_document:
    if length == 1 and (.[0] | type == "object" and (has("error") | not))
    then .[0] else error("expected one object") end;
  def complete_list:
    (.items | type == "array") and optional("metadata"; "object")
    and (.metadata.continue | . == null or . == "")
    and (.metadata.remainingItemCount | . == null or . == 0);
'
# Namespaces whose pods are expected to need host access; findings there are skipped.
system_ns_re=${SYSTEM_NAMESPACES:-'^(kube-system|gke-managed-.*|gmp-system)$'}

findings=$(jq -rs --arg sys "$system_ns_re" "$list_validation"'
  def flag($key): optional($key; "boolean");
  def security_context:
    . == null or (type == "object" and flag("privileged")
      and flag("allowPrivilegeEscalation") and flag("runAsNonRoot")
      and (.runAsUser | . == null or (type == "number" and floor == . and . >= 0)));
  def containers:
    type == "array" and all(.[]; type == "object" and (.name | nonblank)
      and (.securityContext | security_context));
  def valid_podspec:
    type == "object" and (.containers | containers and length > 0)
    and (.initContainers == null or (.initContainers | containers))
    and (.ephemeralContainers == null or (.ephemeralContainers | containers))
    and (.securityContext | security_context)
    and flag("hostPID") and flag("hostIPC") and flag("hostNetwork")
    and (.volumes == null or (.volumes | type == "array" and all(.[];
      type == "object" and (.name | nonblank) and optional("hostPath"; "object"))));
  def workload_kind:
    (.kind // "Pod") | IN("Pod", "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "CronJob");
  # Container value, else pod value, else default. `//` would treat false as missing.
  def eff($sc; $psc; $k; $d): if $sc[$k] != null then $sc[$k] elif $psc[$k] != null then $psc[$k] else $d end;
  # Pod spec of a Pod (items from `kubectl get pods` may omit kind) or a workload wrapper.
  def podspec:
    (.kind // "Pod") as $k
    | if $k == "Pod" then .spec
      elif $k | IN("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job") then .spec.template.spec
      elif $k == "CronJob" then .spec.jobTemplate.spec.template.spec
      else null end;
  one_document
  | if has("items") then
      if ((.kind // "List") | IN("List", "PodList", "DeploymentList", "StatefulSetList",
           "DaemonSetList", "ReplicaSetList", "JobList", "CronJobList")) and complete_list
      then .items else error("invalid or partial workload list") end
    else [.] end
  | if all(.[]; type == "object" and optional("kind"; "string"))
    then . else error("invalid workload list item") end
  | map(select(workload_kind)) as $workloads
  | if length > 0 and ($workloads | length == 0) then error("no supported workload kinds") else $workloads end
  | if all(.[]; optional("metadata"; "object")
      and (.metadata | optional("name"; "string") and optional("generateName"; "string")
        and optional("namespace"; "string"))
      and (podspec | valid_podspec))
    then . else error("invalid workload spec") end
  | ("" | test($sys)) as $namespace_pattern_valid
  | .[]
  | select((.metadata.namespace // "default") | test($sys) | not)
  | (podspec // empty) as $s
  | ((.metadata.namespace // "default") + "/"
     + (if (.kind // "Pod") == "Pod" then "" else (.kind | ascii_downcase) + "/" end)
     + ([.metadata.name, .metadata.generateName, "<unnamed>"] | map(select(. != null and . != "")) | first)) as $id
  | ($s.securityContext // {}) as $psc
  | (
      (if $s.hostPID then "5.2 host namespaces\t\($id)\thostPID" else empty end),
      (if $s.hostIPC then "5.2 host namespaces\t\($id)\thostIPC" else empty end),
      (if $s.hostNetwork then "5.2 host namespaces\t\($id)\thostNetwork" else empty end),
      ($s.volumes // [] | .[] | select(.hostPath) | "5.2 HostPath volumes\t\($id)\tvolume \(.name)"),
      (($s.initContainers // []) + ($s.containers // []) + ($s.ephemeralContainers // []) | .[]
        | (.securityContext // {}) as $sc
        | (
            (if $sc.privileged then "5.2 privileged containers\t\($id)\tcontainer \(.name)" else empty end),
            (if eff($sc; {}; "allowPrivilegeEscalation"; true) then "5.2 privilege escalation\t\($id)\tcontainer \(.name)" else empty end),
            (if (eff($sc; $psc; "runAsNonRoot"; false) | not) or (eff($sc; $psc; "runAsUser"; -1) == 0)
              then "5.2 root containers\t\($id)\tcontainer \(.name)" else empty end)
          ))
    )
' 2>/dev/null <<<"$pods") || input_error "expected one complete workload export and a valid namespace pattern"

admin=$(jq -rs "$list_validation"'
  def binding:
    type == "object" and ((.kind // "ClusterRoleBinding") == "ClusterRoleBinding")
    and (.metadata.name | nonblank)
    and (.roleRef | type == "object" and .kind == "ClusterRole" and (.name | nonblank))
    and (.subjects == null or (.subjects | type == "array" and all(.[];
      type == "object" and (.kind | IN("Group", "User", "ServiceAccount"))
      and (.name | nonblank) and optional("namespace"; "string"))));
  one_document
  | if ((.kind // "List") | IN("List", "ClusterRoleBindingList")) and complete_list
       and all(.items[]; binding)
    then .items[] else error("invalid or partial binding list") end
  | select(.roleRef.kind == "ClusterRole" and .roleRef.name == "cluster-admin")
  | .metadata.name as $b
  | (.subjects // [])[]
  | select(.kind != "Group" or .name != "system:masters")
  | "5.1 cluster-admin use\tclusterrolebinding/\($b)\t\(.kind) \(.namespace // "" | if . == "" then "" else . + "/" end)\(.name)"
' 2>/dev/null <<<"$crb") || input_error "expected one complete cluster role binding export"

all=$(printf '%s\n%s\n' "$findings" "$admin" | sed '/^$/d' | sort -u)
if [ -z "$all" ]; then
  echo "no findings"
  exit 0
fi
printf 'CONTROL\tOBJECT\tDETAIL\n%s\n' "$all" | awk -F'\t' '{ printf "%-28s %-40s %s\n", $1, $2, $3 }'
echo "findings: $(wc -l <<<"$all")"
exit 1
