# GKE configuration review

Read fixture-backed GKE findings and distinguish a failing control from a warning that needs review. Allow 30 minutes. Install Bash and jq.

## Exercise

Run the report from the repository root. The subshell stops on setup errors and removes its temporary copy.

```bash
(
  set -eu
  lab_dir=$(mktemp -d)
  trap 'rm -rf -- "$lab_dir"' EXIT
  checks/gke/gke-report.sh --file checks/gke/fixtures/cluster-good.json
  status=0
  checks/gke/gke-report.sh --file checks/gke/fixtures/cluster-bad.json || status=$?
  test "$status" -eq 1
  jq '.binaryAuthorization.evaluationMode = "DISABLED"' \
    checks/gke/fixtures/cluster-good.json > "$lab_dir/cluster-warn.json"
  checks/gke/gke-report.sh --file "$lab_dir/cluster-warn.json"
)
```

## Verify and clean up

The good fixture reports zero failures. The bad fixture reports nine failures. The modified good fixture reports a warning for Binary Authorization and still exits 0. Record a remediation owner and follow-up for one failure and an explicit risk decision for the warning. Keep the fixture name, status and control output as evidence. The temporary fixture is removed when the subshell exits.

Related reading: [GKE hardening check](/checks/gke/) and [Kubernetes and GKE](/kubernetes/).
