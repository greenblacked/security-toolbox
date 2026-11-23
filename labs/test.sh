#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

lab_dir=$(mktemp -d)
trap 'rm -rf -- "$lab_dir"' EXIT
mkdir "$lab_dir/bin"
# Any accidental fallback to a live client fails and leaves a marker.
printf '#!/usr/bin/env bash\ntouch %q\nexit 97\n' "$lab_dir/live-call" > "$lab_dir/bin/kubectl"
chmod +x "$lab_dir/bin/kubectl"
export PATH="$lab_dir/bin:$PATH"

status=0
labs/kubernetes-workload.sh checks/kubernetes/fixtures/pods-good.json > "$lab_dir/missing.log" 2>&1 || status=$?
test "$status" -eq 2
status=0
labs/kubernetes-workload.sh checks/kubernetes/fixtures/pods-good.json "$lab_dir/absent.json" \
  > "$lab_dir/missing-file.log" 2>&1 || status=$?
test "$status" -eq 2
labs/kubernetes-workload.sh checks/kubernetes/fixtures/pods-good.json \
  checks/kubernetes/fixtures/bindings-good.json > "$lab_dir/good.log"
grep -qx 'no findings' "$lab_dir/good.log"
status=0
labs/kubernetes-workload.sh checks/kubernetes/fixtures/pods-bad.json \
  checks/kubernetes/fixtures/bindings-bad.json > "$lab_dir/bad.log" || status=$?
test "$status" -eq 1
grep -qx 'findings: 14' "$lab_dir/bad.log"
test ! -e "$lab_dir/live-call"

jq '.binaryAuthorization.evaluationMode = "DISABLED"' \
  checks/gke/fixtures/cluster-good.json > "$lab_dir/cluster-warn.json"
checks/gke/gke-report.sh --file "$lab_dir/cluster-warn.json" > "$lab_dir/warn.log"
grep -q '^WARN  Binary Authorization enforced ' "$lab_dir/warn.log"
grep -qx 'failures: 0' "$lab_dir/warn.log"

node labs/detection-regression.mjs labs/fixtures/detection-complete.json > "$lab_dir/complete.json"
jq -e '.alerts == [{"rule":"unexpected-role-grant","actor":"temporary-user","role":"admin"}]
  and .missingSources == []' "$lab_dir/complete.json" > /dev/null
node labs/detection-regression.mjs labs/fixtures/detection-missing-audit.json > "$lab_dir/missing-audit.json"
jq -e '.alerts == [] and .missingSources == ["audit"]' "$lab_dir/missing-audit.json" > /dev/null

node labs/ci-identity.mjs > "$lab_dir/claims.jsonl"
jq -es '
  (map(select(.allowed) | .name) == ["github-allowed", "gitlab-allowed"]) and
  (map(select(.allowed | not) | .mismatches) ==
    [["aud"], ["iss"], ["repository_id"], ["environment"], ["ref_protected"]])
' "$lab_dir/claims.jsonl" > /dev/null
bash labs/artifact-provenance.sh > "$lab_dir/provenance.log"
grep -Fxq 'PASS: release signature, trusted provenance, artifact digest and SBOM digest' "$lab_dir/provenance.log"
grep -Fxq 'REJECT: valid release signature paired with untrusted provenance' "$lab_dir/provenance.log"
grep -Fxq 'REJECT: trusted provenance for a different artifact' "$lab_dir/provenance.log"

echo "Lab checks passed"
