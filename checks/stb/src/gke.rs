//! GKE cluster hardening controls, ported from `checks/gke/gke-report.sh`.
//!
//! Each control mirrors the jq expression in the shell report, including jq's
//! semantics: indexing `null` gives `null`, indexing any other non-object is an
//! error, `a // b` falls back only on `null` or `false`, and an expression that
//! errors is not `true`, so the control is reported at its level.

use anyhow::{Result, bail};
use serde::Serialize;
use serde_json::Value;

/// How serious a control is when it does not pass.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    /// A blocker for a production cluster; makes the exit code 1.
    Fail,
    /// Needs a recorded reason if left off; does not change the exit code.
    Warn,
}

/// The outcome of one control.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pass,
    Fail,
    Warn,
}

impl Status {
    pub fn label(self) -> &'static str {
        match self {
            Status::Pass => "PASS",
            Status::Fail => "FAIL",
            Status::Warn => "WARN",
        }
    }
}

/// jq raised an error (for example indexing a string); the control is not `true`.
struct TypeError;

type Eval = Result<bool, TypeError>;

pub struct Rule {
    pub id: &'static str,
    pub control: &'static str,
    pub level: Level,
    /// Remediation shown when the control does not pass.
    pub detail: &'static str,
    /// Why the control matters, from the checklist in `checks/gke/README.md`.
    pub why: &'static str,
    eval: fn(&Value) -> Eval,
}

pub struct Outcome {
    pub rule: &'static Rule,
    pub status: Status,
}

pub struct Report {
    pub name: String,
    pub location: String,
    pub outcomes: Vec<Outcome>,
}

impl Report {
    pub fn failures(&self) -> usize {
        self.count(Status::Fail)
    }

    pub fn warnings(&self) -> usize {
        self.count(Status::Warn)
    }

    pub fn passed(&self) -> usize {
        self.count(Status::Pass)
    }

    fn count(&self, status: Status) -> usize {
        self.outcomes.iter().filter(|o| o.status == status).count()
    }
}

/// Evaluates every control against one `gcloud container clusters describe` document.
pub fn evaluate(cluster: &Value) -> Result<Report> {
    if !cluster.is_object() {
        bail!("expected a JSON object from `gcloud container clusters describe --format=json`");
    }
    let outcomes = RULES
        .iter()
        .map(|rule| {
            let passed = matches!((rule.eval)(cluster), Ok(true));
            let status = match (passed, rule.level) {
                (true, _) => Status::Pass,
                (false, Level::Fail) => Status::Fail,
                (false, Level::Warn) => Status::Warn,
            };
            Outcome { rule, status }
        })
        .collect();
    Ok(Report {
        name: raw(cluster, "name"),
        location: raw(cluster, "location"),
        outcomes,
    })
}

/// `jq -r '.KEY // "unknown"'` on the cluster object.
fn raw(cluster: &Value, key: &str) -> String {
    match cluster.get(key) {
        None | Some(Value::Null | Value::Bool(false)) => "unknown".to_owned(),
        Some(Value::String(s)) => s.clone(),
        Some(other) => other.to_string(),
    }
}

static NULL: Value = Value::Null;

/// jq `.key`: `null` on `null` or a missing key, an error on non-objects.
fn field<'a>(value: &'a Value, key: &str) -> Result<&'a Value, TypeError> {
    match value {
        Value::Null => Ok(&NULL),
        Value::Object(map) => Ok(map.get(key).unwrap_or(&NULL)),
        _ => Err(TypeError),
    }
}

/// jq `.a.b.c`.
fn path<'a>(value: &'a Value, keys: &[&str]) -> Result<&'a Value, TypeError> {
    keys.iter().try_fold(value, |v, key| field(v, key))
}

/// Whether jq's `//` would fall back to its right-hand side.
fn is_falsy(value: &Value) -> bool {
    matches!(value, Value::Null | Value::Bool(false))
}

fn is_true(value: &Value) -> bool {
    matches!(value, Value::Bool(true))
}

/// `(X // "DEFAULT")` used as a string: the default when `X` is falsy, an error
/// when `X` is not a string.
fn str_or<'a>(value: &'a Value, default: &'a str) -> Result<&'a str, TypeError> {
    if is_falsy(value) {
        Ok(default)
    } else {
        value.as_str().ok_or(TypeError)
    }
}

/// `[.nodePools[]? | F] | (length > 0 and all)`.
fn all_node_pools(cluster: &Value, check: impl Fn(&Value) -> Eval) -> Eval {
    let pools: Vec<&Value> = match field(cluster, "nodePools") {
        Ok(Value::Array(items)) => items.iter().collect(),
        Ok(Value::Object(map)) => map.values().collect(),
        _ => Vec::new(),
    };
    let mut all = true;
    for pool in &pools {
        // An error on any pool fails the whole expression, as in jq.
        all &= check(pool)?;
    }
    Ok(!pools.is_empty() && all)
}

fn workload_identity(c: &Value) -> Eval {
    let pool = path(c, &["workloadIdentityConfig", "workloadPool"])?;
    Ok(str_or(pool, "")?.ends_with(".svc.id.goog"))
}

fn gke_metadata_server(c: &Value) -> Eval {
    all_node_pools(c, |p| {
        Ok(
            path(p, &["config", "workloadMetadataConfig", "mode"])?.as_str()
                == Some("GKE_METADATA"),
        )
    })
}

fn shielded_nodes(c: &Value) -> Eval {
    Ok(is_true(path(c, &["shieldedNodes", "enabled"])?))
}

fn secure_boot(c: &Value) -> Eval {
    all_node_pools(c, |p| {
        Ok(is_true(path(
            p,
            &["config", "shieldedInstanceConfig", "enableSecureBoot"],
        )?))
    })
}

fn integrity_monitoring(c: &Value) -> Eval {
    all_node_pools(c, |p| {
        Ok(is_true(path(
            p,
            &[
                "config",
                "shieldedInstanceConfig",
                "enableIntegrityMonitoring",
            ],
        )?))
    })
}

fn binary_authorization(c: &Value) -> Eval {
    let mode = path(c, &["binaryAuthorization", "evaluationMode"])?;
    Ok(str_or(mode, "DISABLED")?.contains("ENFORCE"))
}

fn network_policy(c: &Value) -> Eval {
    // jq `or` short-circuits: the right side is only evaluated when the left is false.
    if path(c, &["networkConfig", "datapathProvider"])?.as_str() == Some("ADVANCED_DATAPATH") {
        return Ok(true);
    }
    Ok(is_true(path(c, &["networkPolicy", "enabled"])?))
}

fn private_nodes(c: &Value) -> Eval {
    Ok(is_true(path(
        c,
        &["privateClusterConfig", "enablePrivateNodes"],
    )?))
}

fn authorised_networks(c: &Value) -> Eval {
    Ok(is_true(path(
        c,
        &["masterAuthorizedNetworksConfig", "enabled"],
    )?))
}

fn legacy_abac_disabled(c: &Value) -> Eval {
    // (.legacyAbac.enabled // false) == false
    Ok(is_falsy(path(c, &["legacyAbac", "enabled"])?))
}

fn no_client_certificate(c: &Value) -> Eval {
    // (.masterAuth.clientKey // "") == ""
    let key = path(c, &["masterAuth", "clientKey"])?;
    Ok(is_falsy(key) || key.as_str() == Some(""))
}

fn dedicated_node_sa(c: &Value) -> Eval {
    all_node_pools(c, |p| {
        let sa = path(p, &["config", "serviceAccount"])?;
        // (sa // "default") != "default"
        if is_falsy(sa) || sa.as_str() == Some("default") {
            return Ok(false);
        }
        // and ((sa // "") | test("-compute@developer") | not)
        Ok(!str_or(sa, "")?.contains("-compute@developer"))
    })
}

fn release_channel(c: &Value) -> Eval {
    // (.releaseChannel.channel // "UNSPECIFIED") != "UNSPECIFIED"
    let channel = path(c, &["releaseChannel", "channel"])?;
    Ok(!is_falsy(channel) && channel.as_str() != Some("UNSPECIFIED"))
}

fn node_auto_upgrade(c: &Value) -> Eval {
    all_node_pools(c, |p| Ok(is_true(path(p, &["management", "autoUpgrade"])?)))
}

/// The controls, in the order the shell report prints them.
pub static RULES: [Rule; 14] = [
    Rule {
        id: "gke-workload-identity",
        control: "Workload Identity",
        level: Level::Fail,
        detail: "enable with --workload-pool=PROJECT_ID.svc.id.goog",
        why: "Pods get short-lived Google credentials for a specific Kubernetes service account instead of the node's identity or an exported key.",
        eval: workload_identity,
    },
    Rule {
        id: "gke-metadata-server",
        control: "Node pools use GKE metadata server",
        level: Level::Fail,
        detail: "set --workload-metadata=GKE_METADATA on every node pool",
        why: "Without it, pods can read the node service account token from the Compute metadata server.",
        eval: gke_metadata_server,
    },
    Rule {
        id: "gke-shielded-nodes",
        control: "Shielded GKE Nodes",
        level: Level::Fail,
        detail: "enable with --enable-shielded-nodes",
        why: "Node identity is verified, so a compromised pod cannot impersonate a node to join the cluster.",
        eval: shielded_nodes,
    },
    Rule {
        id: "gke-secure-boot",
        control: "Secure Boot on node pools",
        level: Level::Warn,
        detail: "create node pools with --shielded-secure-boot",
        why: "Blocks unsigned kernel modules; breaks some third-party drivers, so test first.",
        eval: secure_boot,
    },
    Rule {
        id: "gke-integrity-monitoring",
        control: "Integrity monitoring on node pools",
        level: Level::Fail,
        detail: "create node pools with --shielded-integrity-monitoring",
        why: "Detects boot-level tampering on nodes.",
        eval: integrity_monitoring,
    },
    Rule {
        id: "gke-binary-authorization",
        control: "Binary Authorization enforced",
        level: Level::Warn,
        detail: "set --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE and define a policy",
        why: "Only images that meet a policy (allowed registries, attestations from your build) are admitted.",
        eval: binary_authorization,
    },
    Rule {
        id: "gke-network-policy",
        control: "NetworkPolicy enforcement",
        level: Level::Fail,
        detail: "use GKE Dataplane V2 (--enable-dataplane-v2) or enable network policy",
        why: "Without an enforcing dataplane, NetworkPolicy objects are silently ignored.",
        eval: network_policy,
    },
    Rule {
        id: "gke-private-nodes",
        control: "Private nodes",
        level: Level::Fail,
        detail: "nodes have public IPs; use --enable-private-nodes",
        why: "Nodes without external IPs are not directly reachable from the internet.",
        eval: private_nodes,
    },
    Rule {
        id: "gke-authorised-networks",
        control: "Control plane authorised networks",
        level: Level::Warn,
        detail: "restrict control plane access with --enable-master-authorized-networks",
        why: "Limits who can reach the Kubernetes API endpoint.",
        eval: authorised_networks,
    },
    Rule {
        id: "gke-legacy-abac",
        control: "Legacy ABAC disabled",
        level: Level::Fail,
        detail: "disable with --no-enable-legacy-authorization",
        why: "ABAC grants bypass RBAC.",
        eval: legacy_abac_disabled,
    },
    Rule {
        id: "gke-client-certificate",
        control: "No client certificate issued",
        level: Level::Fail,
        detail: "cluster issued a static client certificate; rotate credentials and stop issuing it",
        why: "A client certificate is a non-revocable cluster credential.",
        eval: no_client_certificate,
    },
    Rule {
        id: "gke-node-service-account",
        control: "Node SA is not the default compute SA",
        level: Level::Fail,
        detail: "use a dedicated least-privilege node service account",
        why: "The Compute default service account usually holds Editor on the project.",
        eval: dedicated_node_sa,
    },
    Rule {
        id: "gke-release-channel",
        control: "Release channel set",
        level: Level::Warn,
        detail: "enrol in a release channel (REGULAR or STABLE)",
        why: "Security patches arrive on a schedule instead of when someone remembers.",
        eval: release_channel,
    },
    Rule {
        id: "gke-node-auto-upgrade",
        control: "Node auto-upgrade",
        level: Level::Warn,
        detail: "enable auto-upgrade on every node pool",
        why: "Keeps node images patched.",
        eval: node_auto_upgrade,
    },
];
