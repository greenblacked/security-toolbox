#!/usr/bin/env bash
set -euo pipefail

repo=greenblacked/security-toolbox
endpoint="repos/$repo/environments/production"

# Do not change the environment mode or any existing rules.
environment=$(gh api "$endpoint")
if ! jq -e '.deployment_branch_policy | .custom_branch_policies == true and .protected_branches == false' <<<"$environment" >/dev/null; then
  echo 'Production must use Selected branches and tags before running this script.' >&2
  exit 1
fi

count_prod_rules() {
  local pages
  pages=$(gh api --paginate --slurp "$endpoint/deployment-branch-policies?per_page=100") || return 1
  [[ -n $pages ]] || return 1
  jq -er '
    if (type == "array" and length > 0 and all(.[]; (.branch_policies | type) == "array")) then
      [.[].branch_policies[] | select(.name == "prod" and .type == "branch")] | length
    else error("Invalid deployment branch policy response") end
  ' <<<"$pages"
}

count=$(count_prod_rules)
if [[ $count == 0 ]]; then
  gh api --method POST "$endpoint/deployment-branch-policies" -f name=prod -f type=branch >/dev/null
  echo 'Added the prod branch deployment policy.'
else
  echo 'The prod branch deployment policy already exists.'
fi

count=$(count_prod_rules)
if [[ $count == 0 ]]; then
  echo 'Verification failed: prod branch policy not found.' >&2
  exit 1
fi
echo 'Verified: production allows the prod branch.'
