#!/usr/bin/env bash
# Read-only GCP project IAM baseline report.
#
#   checks/gcp/iam-report.sh --project ID [--domain example.com]
#   checks/gcp/iam-report.sh --file policy.json   # output of `gcloud projects get-iam-policy ID --format=json`
#
# Prints PASS / FAIL / WARN per control. Exits 1 if any FAIL, 0 otherwise.
# Needs jq; needs gcloud with resourcemanager.projects.getIamPolicy unless --file is used.
set -Eeuo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

file='' project='' domain=''
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file=${2:?}; shift 2 ;;
    --project) project=${2:?}; shift 2 ;;
    --domain) domain=${2:?}; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

if [ -n "$file" ]; then
  json=$(cat -- "$file")
elif [ -n "$project" ]; then
  json=$(gcloud projects get-iam-policy "$project" --format=json)
else
  usage
fi

fails=0
report() { # report <PASS|FAIL|WARN> <control> <detail>
  printf '%-4s  %-42s %s\n' "$1" "$2" "$3"
  if [ "$1" = FAIL ]; then fails=$((fails + 1)); fi
}
q() { jq -r "$1" <<<"$json"; }
check() { # check <control> <jq boolean expr> <fail detail> [WARN]
  local level=${4:-FAIL}
  if [ "$(q "$2")" = true ]; then report PASS "$1" ""; else report "$level" "$1" "$3"; fi
}

echo "source: ${file:-project $project}"
echo "bindings: $(q '(.bindings // []) | length')"
echo

check "No public members" \
  '[.bindings[]? | .members[]? | select(. == "allUsers" or . == "allAuthenticatedUsers")] | length == 0' \
  "a binding grants the internet; remove it and set storage.publicAccessPrevention"
check "No unconditional basic roles" \
  '[.bindings[]? | select(.condition == null) | select(.role == "roles/owner" or .role == "roles/editor")] | length == 0' \
  "replace roles/owner and roles/editor with predefined roles; a condition makes one time-bound"
check "No unconditional roles/viewer" \
  '[.bindings[]? | select(.condition == null) | select(.role == "roles/viewer")] | length == 0' \
  "roles/viewer reads every resource in the project; grant a service-specific viewer" WARN
check "Default compute SA holds no basic role" \
  '[.bindings[]? | select(.role == "roles/owner" or .role == "roles/editor") | .members[]?
    | select(test("^serviceAccount:[0-9]+-compute@developer\\.gserviceaccount\\.com$"))] | length == 0' \
  "workloads inheriting the default account inherit this; use a dedicated service account"
check "No project-wide token creator" \
  '[.bindings[]? | select(.role == "roles/iam.serviceAccountTokenCreator")] | length == 0' \
  "project-wide impersonation reaches every service account; scope it to one account" WARN
check "No project-wide security admin" \
  '[.bindings[]? | select(.role == "roles/iam.securityAdmin")] | length == 0' \
  "securityAdmin can grant itself anything; keep it in a break-glass group" WARN
check "No bindings to individual users" \
  '[.bindings[]? | .members[]? | select(startswith("user:"))] | length == 0' \
  "bind groups so access reviews and offboarding happen in the identity provider" WARN

# Only meaningful when the caller says which domain is allowed; the organisation
# policy constraint iam.allowedPolicyMemberDomains is the enforcement.
if [ -n "$domain" ]; then
  outside=$(jq -r --arg d "$domain" '[.bindings[]? | .members[]?
    | select(startswith("user:") or startswith("group:"))
    | (split(":")[1] | split("@") | .[1] // "") as $member_domain
    | select($member_domain != $d)] | length' <<<"$json")
  if [ "$outside" = 0 ]; then
    report PASS "Members inside $domain" ""
  else
    report WARN "Members inside $domain" "$outside member(s) from another domain"
  fi
fi

echo
echo "failures: $fails"
[ "$fails" -eq 0 ]
