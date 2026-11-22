//! Integration tests for `stb gke`, run against the built binary.

use std::path::PathBuf;
use std::process::Output;

use assert_cmd::Command;
use serde_json::{Value, json};

/// The 9 FAIL and 5 WARN controls that `checks/gke/fixtures/cluster-bad.json` trips.
const BAD_FAILS: [&str; 9] = [
    "gke-workload-identity",
    "gke-metadata-server",
    "gke-shielded-nodes",
    "gke-integrity-monitoring",
    "gke-network-policy",
    "gke-private-nodes",
    "gke-legacy-abac",
    "gke-client-certificate",
    "gke-node-service-account",
];
const BAD_WARNS: [&str; 5] = [
    "gke-secure-boot",
    "gke-binary-authorization",
    "gke-authorised-networks",
    "gke-release-channel",
    "gke-node-auto-upgrade",
];

/// What `checks/gke/gke-report.sh --file checks/gke/fixtures/cluster-bad.json` prints.
const BAD_TEXT: &str = "\
cluster: legacy  location: europe-west1-b
FAIL  Workload Identity                      enable with --workload-pool=PROJECT_ID.svc.id.goog
FAIL  Node pools use GKE metadata server     set --workload-metadata=GKE_METADATA on every node pool
FAIL  Shielded GKE Nodes                     enable with --enable-shielded-nodes
WARN  Secure Boot on node pools              create node pools with --shielded-secure-boot
FAIL  Integrity monitoring on node pools     create node pools with --shielded-integrity-monitoring
WARN  Binary Authorization enforced          set --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE and define a policy
FAIL  NetworkPolicy enforcement              use GKE Dataplane V2 (--enable-dataplane-v2) or enable network policy
FAIL  Private nodes                          nodes have public IPs; use --enable-private-nodes
WARN  Control plane authorised networks      restrict control plane access with --enable-master-authorized-networks
FAIL  Legacy ABAC disabled                   disable with --no-enable-legacy-authorization
FAIL  No client certificate issued           cluster issued a static client certificate; rotate credentials and stop issuing it
FAIL  Node SA is not the default compute SA  use a dedicated least-privilege node service account
WARN  Release channel set                    enrol in a release channel (REGULAR or STABLE)
WARN  Node auto-upgrade                      enable auto-upgrade on every node pool
failures: 9
";

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../gke/fixtures")
        .join(name)
}

fn load(name: &str) -> Value {
    serde_json::from_slice(&std::fs::read(fixture(name)).unwrap()).unwrap()
}

fn stb() -> Command {
    Command::new(env!("CARGO_BIN_EXE_stb"))
}

fn run_file(name: &str, format: &str) -> Output {
    stb()
        .args(["gke", "--format", format, "--file"])
        .arg(fixture(name))
        .output()
        .unwrap()
}

fn run_stdin(input: impl Into<Vec<u8>>, args: &[&str]) -> Output {
    stb()
        .arg("gke")
        .args(args)
        .write_stdin(input)
        .output()
        .unwrap()
}

fn run_json(cluster: &Value) -> (i32, Value) {
    let out = run_stdin(cluster.to_string(), &["--format", "json"]);
    let code = out.status.code().unwrap();
    (code, serde_json::from_slice(&out.stdout).unwrap())
}

fn stdout(out: &Output) -> &str {
    std::str::from_utf8(&out.stdout).unwrap()
}

fn stderr(out: &Output) -> &str {
    std::str::from_utf8(&out.stderr).unwrap()
}

/// Rule id to status from the JSON report.
fn statuses(report: &Value) -> Vec<(String, String)> {
    report["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["id"].as_str().unwrap().to_owned(),
                r["status"].as_str().unwrap().to_owned(),
            )
        })
        .collect()
}

fn ids_with(report: &Value, status: &str) -> Vec<String> {
    statuses(report)
        .into_iter()
        .filter(|(_, s)| s == status)
        .map(|(id, _)| id)
        .collect()
}

// --- parity with checks/gke/gke-report.sh -----------------------------------

#[test]
fn bad_fixture_text_matches_shell_report() {
    let out = run_file("cluster-bad.json", "text");
    assert_eq!(out.status.code(), Some(1));
    assert_eq!(stdout(&out), BAD_TEXT);
    assert!(stdout(&out).lines().any(|l| l == "failures: 9"));
}

#[test]
fn good_fixture_is_clean() {
    let out = run_file("cluster-good.json", "text");
    assert_eq!(out.status.code(), Some(0), "{}", stdout(&out));
    let text = stdout(&out);
    assert!(text.starts_with("cluster: prod  location: europe-west1\n"));
    assert_eq!(text.lines().filter(|l| l.starts_with("PASS  ")).count(), 14);
    assert!(text.ends_with("failures: 0\n"));
}

#[test]
fn bad_fixture_json_has_nine_failures_and_five_warnings() {
    let out = run_file("cluster-bad.json", "json");
    assert_eq!(out.status.code(), Some(1));
    let report: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(report["check"], "gke");
    assert_eq!(
        report["cluster"],
        json!({"name": "legacy", "location": "europe-west1-b"})
    );
    assert_eq!(
        report["summary"],
        json!({"failures": 9, "warnings": 5, "passed": 0})
    );
    assert_eq!(ids_with(&report, "fail"), BAD_FAILS);
    assert_eq!(ids_with(&report, "warn"), BAD_WARNS);
}

#[test]
fn good_fixture_json_has_no_findings() {
    let out = run_file("cluster-good.json", "json");
    assert_eq!(out.status.code(), Some(0));
    let report: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(
        report["summary"],
        json!({"failures": 0, "warnings": 0, "passed": 14})
    );
    assert!(
        report["results"]
            .as_array()
            .unwrap()
            .iter()
            .all(|r| r.get("detail").is_none())
    );
}

// --- every rule ---------------------------------------------------------------

/// Breaks exactly one control on the good fixture and checks that only that
/// control changes, at its level, with the matching exit code.
fn assert_only(rule: &str, level: &str, mutate: impl FnOnce(&mut Value)) {
    let mut cluster = load("cluster-good.json");
    mutate(&mut cluster);
    let (code, report) = run_json(&cluster);
    for (id, status) in statuses(&report) {
        let want = if id == rule { level } else { "pass" };
        assert_eq!(status, want, "rule {id} after breaking {rule}");
    }
    let want_code = if level == "fail" { 1 } else { 0 };
    assert_eq!(code, want_code, "exit code after breaking {rule}");
}

fn pool(cluster: &mut Value) -> &mut Value {
    &mut cluster["nodePools"][0]
}

#[test]
fn rule_workload_identity() {
    assert_only("gke-workload-identity", "fail", |c| {
        c.as_object_mut().unwrap().remove("workloadIdentityConfig");
    });
    assert_only("gke-workload-identity", "fail", |c| {
        c["workloadIdentityConfig"]["workloadPool"] = json!("example-project.example.com");
    });
    // A non-string pool is a jq error, which is never `true`.
    assert_only("gke-workload-identity", "fail", |c| {
        c["workloadIdentityConfig"]["workloadPool"] = json!(42);
    });
}

#[test]
fn rule_metadata_server() {
    assert_only("gke-metadata-server", "fail", |c| {
        pool(c)["config"]["workloadMetadataConfig"]["mode"] = json!("GCE_METADATA");
    });
    // Every node pool must comply, not just the first.
    assert_only("gke-metadata-server", "fail", |c| {
        let mut second = pool(c).clone();
        second["config"]["workloadMetadataConfig"]["mode"] = json!("MODE_UNSPECIFIED");
        c["nodePools"].as_array_mut().unwrap().push(second);
    });
}

#[test]
fn rule_shielded_nodes() {
    assert_only("gke-shielded-nodes", "fail", |c| {
        c["shieldedNodes"]["enabled"] = json!(false);
    });
    // Only boolean true passes.
    assert_only("gke-shielded-nodes", "fail", |c| {
        c["shieldedNodes"]["enabled"] = json!("true");
    });
}

#[test]
fn rule_secure_boot() {
    assert_only("gke-secure-boot", "warn", |c| {
        pool(c)["config"]["shieldedInstanceConfig"]["enableSecureBoot"] = json!(false);
    });
}

#[test]
fn rule_integrity_monitoring() {
    assert_only("gke-integrity-monitoring", "fail", |c| {
        pool(c)["config"]["shieldedInstanceConfig"]
            .as_object_mut()
            .unwrap()
            .remove("enableIntegrityMonitoring");
    });
}

#[test]
fn rule_binary_authorization() {
    assert_only("gke-binary-authorization", "warn", |c| {
        c["binaryAuthorization"]["evaluationMode"] = json!("DISABLED");
    });
    assert_only("gke-binary-authorization", "warn", |c| {
        c.as_object_mut().unwrap().remove("binaryAuthorization");
    });
}

#[test]
fn rule_network_policy() {
    assert_only("gke-network-policy", "fail", |c| {
        c["networkConfig"]["datapathProvider"] = json!("LEGACY_DATAPATH");
    });
    // The legacy dataplane passes when network policy enforcement is on.
    let mut cluster = load("cluster-good.json");
    cluster["networkConfig"]["datapathProvider"] = json!("LEGACY_DATAPATH");
    cluster["networkPolicy"] = json!({"enabled": true});
    let (code, report) = run_json(&cluster);
    assert_eq!(code, 0);
    assert!(ids_with(&report, "fail").is_empty());
}

#[test]
fn rule_private_nodes() {
    assert_only("gke-private-nodes", "fail", |c| {
        c["privateClusterConfig"]["enablePrivateNodes"] = json!(false);
    });
}

#[test]
fn rule_authorised_networks() {
    assert_only("gke-authorised-networks", "warn", |c| {
        c["masterAuthorizedNetworksConfig"] = json!({});
    });
}

#[test]
fn rule_legacy_abac() {
    assert_only("gke-legacy-abac", "fail", |c| {
        c["legacyAbac"]["enabled"] = json!(true);
    });
    // Explicitly false passes, like a missing value.
    let mut cluster = load("cluster-good.json");
    cluster["legacyAbac"]["enabled"] = json!(false);
    assert_eq!(run_json(&cluster).0, 0);
}

#[test]
fn rule_client_certificate() {
    assert_only("gke-client-certificate", "fail", |c| {
        c["masterAuth"]["clientKey"] = json!("redacted");
    });
    let mut cluster = load("cluster-good.json");
    cluster["masterAuth"]["clientKey"] = json!("");
    assert_eq!(run_json(&cluster).0, 0);
}

#[test]
fn rule_node_service_account() {
    assert_only("gke-node-service-account", "fail", |c| {
        pool(c)["config"]["serviceAccount"] = json!("default");
    });
    assert_only("gke-node-service-account", "fail", |c| {
        pool(c)["config"]["serviceAccount"] =
            json!("123456789-compute@developer.gserviceaccount.com");
    });
    assert_only("gke-node-service-account", "fail", |c| {
        pool(c)["config"]
            .as_object_mut()
            .unwrap()
            .remove("serviceAccount");
    });
}

#[test]
fn rule_release_channel() {
    assert_only("gke-release-channel", "warn", |c| {
        c["releaseChannel"]["channel"] = json!("UNSPECIFIED");
    });
    assert_only("gke-release-channel", "warn", |c| {
        c.as_object_mut().unwrap().remove("releaseChannel");
    });
}

#[test]
fn rule_node_auto_upgrade() {
    assert_only("gke-node-auto-upgrade", "warn", |c| {
        pool(c)["management"]["autoUpgrade"] = json!(false);
    });
}

#[test]
fn no_node_pools_fails_every_node_pool_control() {
    let mut cluster = load("cluster-good.json");
    cluster["nodePools"] = json!([]);
    let (code, report) = run_json(&cluster);
    assert_eq!(code, 1);
    assert_eq!(
        ids_with(&report, "fail"),
        [
            "gke-metadata-server",
            "gke-integrity-monitoring",
            "gke-node-service-account"
        ]
    );
    assert_eq!(
        ids_with(&report, "warn"),
        ["gke-secure-boot", "gke-node-auto-upgrade"]
    );
}

#[test]
fn every_rule_is_exercised() {
    // Keeps the per-rule tests above in step with the rule list.
    let (_, report) = run_json(&load("cluster-good.json"));
    let mut ids: Vec<String> = statuses(&report).into_iter().map(|(id, _)| id).collect();
    let mut covered: Vec<&str> = BAD_FAILS.iter().chain(BAD_WARNS.iter()).copied().collect();
    ids.sort();
    covered.sort_unstable();
    assert_eq!(ids, covered);
}

// --- input -------------------------------------------------------------------

#[test]
fn reads_stdin_when_file_is_omitted() {
    let input = std::fs::read(fixture("cluster-bad.json")).unwrap();
    let out = run_stdin(input, &[]);
    assert_eq!(out.status.code(), Some(1));
    assert_eq!(stdout(&out), BAD_TEXT);
}

#[test]
fn reads_stdin_when_file_is_dash() {
    let input = std::fs::read(fixture("cluster-good.json")).unwrap();
    let out = run_stdin(input, &["--file", "-"]);
    assert_eq!(out.status.code(), Some(0));
    assert!(stdout(&out).ends_with("failures: 0\n"));
}

// --- exit code 2: usage and input errors -----------------------------------

fn assert_input_error(out: &Output, needle: &str) {
    assert_eq!(out.status.code(), Some(2), "stderr: {}", stderr(out));
    assert!(out.stdout.is_empty(), "no report on error");
    assert!(stderr(out).contains(needle), "stderr: {}", stderr(out));
}

#[test]
fn malformed_json_on_stdin_exits_2() {
    let out = run_stdin("{\"name\": \"prod\",", &[]);
    assert_input_error(&out, "malformed JSON in stdin");
}

#[test]
fn malformed_json_file_exits_2() {
    let dir = std::env::temp_dir().join(format!("stb-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("broken.json");
    std::fs::write(&path, "{ not json }").unwrap();
    let out = stb().args(["gke", "--file"]).arg(&path).output().unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
    assert_input_error(&out, "malformed JSON in");
}

#[test]
fn empty_input_exits_2() {
    let out = run_stdin("", &[]);
    assert_input_error(&out, "malformed JSON in stdin");
}

#[test]
fn trailing_data_exits_2() {
    let out = run_stdin("{} {}", &[]);
    assert_input_error(&out, "malformed JSON");
}

#[test]
fn non_object_input_exits_2() {
    for input in ["[]", "null", "\"prod\"", "42"] {
        let out = run_stdin(input, &[]);
        assert_input_error(&out, "expected a JSON object");
    }
}

#[test]
fn missing_file_exits_2() {
    let out = stb()
        .args(["gke", "--file", "does/not/exist.json"])
        .output()
        .unwrap();
    assert_input_error(&out, "cannot read does/not/exist.json");
}

#[test]
fn usage_errors_exit_2() {
    for args in [
        &[][..],
        &["gke", "--format", "xml"][..],
        &["gke", "--unknown"][..],
        &["gke", "--file"][..],
        &["nope"][..],
    ] {
        let out = stb().args(args).write_stdin("{}").output().unwrap();
        assert_eq!(out.status.code(), Some(2), "args {args:?}");
        assert!(out.stdout.is_empty(), "args {args:?}");
    }
}

#[test]
fn help_and_version_exit_0() {
    for args in [&["--help"][..], &["gke", "--help"][..], &["--version"][..]] {
        let out = stb().args(args).output().unwrap();
        assert_eq!(out.status.code(), Some(0), "args {args:?}");
    }
    let help = stb().args(["gke", "--help"]).output().unwrap();
    assert!(stdout(&help).contains("--format <FORMAT>"));
}

// --- SARIF -------------------------------------------------------------------

fn sarif_validator() -> jsonschema::Validator {
    // Vendored copy of https://json.schemastore.org/sarif-2.1.0.json; never fetched at test time.
    let schema: Value = serde_json::from_str(include_str!("fixtures/sarif-2.1.0.json")).unwrap();
    jsonschema::validator_for(&schema).unwrap()
}

fn assert_valid_sarif(log: &Value) {
    let validator = sarif_validator();
    let errors: Vec<String> = validator.iter_errors(log).map(|e| e.to_string()).collect();
    assert!(errors.is_empty(), "SARIF schema errors: {errors:#?}");
}

#[test]
fn sarif_schema_rejects_an_invalid_log() {
    // Guards against a validator that accepts everything.
    let validator = sarif_validator();
    assert!(!validator.is_valid(&json!({"version": "2.1.0"})));
    assert!(!validator.is_valid(&json!({"version": "9.9", "runs": []})));
}

#[test]
fn sarif_bad_fixture_is_valid_and_complete() {
    let out = run_file("cluster-bad.json", "sarif");
    assert_eq!(out.status.code(), Some(1));
    let log: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_valid_sarif(&log);
    assert_eq!(log["version"], "2.1.0");

    let run = &log["runs"][0];
    let rules = run["tool"]["driver"]["rules"].as_array().unwrap();
    assert_eq!(rules.len(), 14);
    let results = run["results"].as_array().unwrap();
    let level_ids = |level: &str| -> Vec<&str> {
        results
            .iter()
            .filter(|r| r["level"] == level)
            .map(|r| r["ruleId"].as_str().unwrap())
            .collect()
    };
    assert_eq!(level_ids("error"), BAD_FAILS);
    assert_eq!(level_ids("warning"), BAD_WARNS);
    for result in results {
        let index = usize::try_from(result["ruleIndex"].as_u64().unwrap()).unwrap();
        assert_eq!(rules[index]["id"], result["ruleId"]);
        let uri = result["locations"][0]["physicalLocation"]["artifactLocation"]["uri"]
            .as_str()
            .unwrap();
        assert!(uri.ends_with("gke/fixtures/cluster-bad.json"), "{uri}");
    }
}

#[test]
fn sarif_good_fixture_is_valid_and_empty() {
    let out = run_file("cluster-good.json", "sarif");
    assert_eq!(out.status.code(), Some(0));
    let log: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_valid_sarif(&log);
    assert_eq!(log["runs"][0]["results"], json!([]));
}

#[test]
fn sarif_from_stdin_is_valid_without_a_file_location() {
    let input = std::fs::read(fixture("cluster-bad.json")).unwrap();
    let out = run_stdin(input, &["--format", "sarif"]);
    assert_eq!(out.status.code(), Some(1));
    let log: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_valid_sarif(&log);
    let location = &log["runs"][0]["results"][0]["locations"][0];
    assert!(location.get("physicalLocation").is_none());
    assert_eq!(location["logicalLocations"][0]["name"], "legacy");
}
