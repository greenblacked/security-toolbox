#!/usr/bin/env bash
# Read-only GCP project IAM baseline report.
#
#   checks/gcp/iam-report.sh --project ID [--domain example.com]
#   checks/gcp/iam-report.sh --file policy.json   # output of `gcloud projects get-iam-policy ID --format=json`
#
# Exits 0 if no control fails, 1 for failed controls, or 2 for unavailable or invalid input.
# Needs jq; needs gcloud with resourcemanager.projects.getIamPolicy unless --file is used.
set -Eeuo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

input_error() {
  printf 'IAM policy input error: %s\n' "$1" >&2
  exit 2
}

file='' project='' domain=''
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ -n "${2-}" ] || input_error "--file requires a value"; file=$2; shift 2 ;;
    --project) [ -n "${2-}" ] || input_error "--project requires a value"; project=$2; shift 2 ;;
    --domain) [ -n "${2-}" ] || input_error "--domain requires a value"; domain=$2; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

if [ -n "$file" ] && [ -n "$project" ]; then
  input_error "use either --file or --project"
fi
command -v jq >/dev/null || input_error "jq is required"
if [ -n "$file" ]; then
  # Parse the bytes before Bash command substitution can drop NUL characters.
  json=$(jq -c . -- "$file" 2>/dev/null) || input_error "could not read a JSON policy export"
elif [ -n "$project" ]; then
  json=$(gcloud projects get-iam-policy "$project" --format=json | jq -c . 2>/dev/null) ||
    input_error "could not fetch project IAM policy"
else
  usage
fi

# Slurp to reject empty input or multiple documents. An etag identifies an
# exported policy when the API omits its empty bindings field.
if ! jq -es '
  def nonblank: type == "string" and test("\\S");
  def binding:
    type == "object" and (.role | nonblank)
    and (.members | type == "array" and length > 0 and all(.[]; nonblank))
    and (if has("condition") then
      (.condition | type == "object" and (.expression | nonblank))
    else true end);
  length == 1 and (.[0] |
    type == "object" and ((keys_unsorted - ["bindings", "auditConfigs", "etag", "version"]) | length == 0)
    and (if has("etag") then (.etag | nonblank) else true end)
    and (if has("version") then (.version == 0 or .version == 1 or .version == 3) else true end)
    and (if has("auditConfigs") then (.auditConfigs | type == "array") else true end)
    and (if has("bindings") then
      (.bindings | type == "array" and all(.[]; binding))
    else (.etag | nonblank) end))
' >/dev/null 2>&1 <<<"$json"; then
  input_error "expected one full project IAM policy JSON export"
fi
if jq -e '.version != 3 and any(.bindings[]?;
  has("condition") or (.role | test("_withcond_[0-9a-fA-F]+$")))' >/dev/null <<<"$json"; then
  input_error "conditional bindings require a complete version 3 policy export"
fi
if jq -e 'any(.bindings[]?; has("condition") and
  ((.role == "roles/owner" or .role == "roles/editor" or .role == "roles/viewer")
  or any(.members[]; . == "allUsers" or . == "allAuthenticatedUsers")))' >/dev/null <<<"$json"; then
  input_error "Google IAM does not support conditions on legacy basic roles or public principals"
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
if jq -e 'has("bindings") | not' >/dev/null <<<"$json"; then
  echo "bindings omitted in export; reporting zero direct bindings only"
fi
echo

check "No public members" \
  '[.bindings[]? | .members[]? | select(. == "allUsers" or . == "allAuthenticatedUsers")] | length == 0' \
  "a binding grants the internet; remove it and set storage.publicAccessPrevention"
check "No unconditional basic roles" \
  '[.bindings[]? | select(.condition == null) | select(.role == "roles/owner" or .role == "roles/editor")] | length == 0' \
  "replace roles/owner and roles/editor with narrowly scoped predefined roles"
check "No unconditional roles/viewer" \
  '[.bindings[]? | select(.condition == null) | select(.role == "roles/viewer")] | length == 0' \
  "roles/viewer grants broad read access; grant a service-specific viewer" WARN
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
