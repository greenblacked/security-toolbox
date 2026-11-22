//! Rendering a report as text, JSON or SARIF 2.1.0.

use std::fmt::Write as _;

use anyhow::Result;
use serde::Serialize;
use serde_json::{Value, json};

use crate::gke::{Level, RULES, Report, Status};

const SARIF_SCHEMA: &str = "https://json.schemastore.org/sarif-2.1.0.json";
const INFORMATION_URI: &str = "https://github.com/greenblacked/security-toolbox";
const HELP_URI: &str =
    "https://github.com/greenblacked/security-toolbox/blob/main/checks/gke/README.md";

/// The same lines `checks/gke/gke-report.sh` prints.
pub fn text(report: &Report) -> String {
    let mut out = format!("cluster: {}  location: {}\n", report.name, report.location);
    for outcome in &report.outcomes {
        let detail = if outcome.status == Status::Pass {
            ""
        } else {
            outcome.rule.detail
        };
        // Matches printf '%-4s  %-38s %s\n'.
        let _ = writeln!(
            out,
            "{:<4}  {:<38} {}",
            outcome.status.label(),
            outcome.rule.control,
            detail
        );
    }
    let _ = writeln!(out, "failures: {}", report.failures());
    out
}

#[derive(Serialize)]
struct JsonReport<'a> {
    check: &'static str,
    cluster: JsonCluster<'a>,
    summary: JsonSummary,
    results: Vec<JsonResult>,
}

#[derive(Serialize)]
struct JsonCluster<'a> {
    name: &'a str,
    location: &'a str,
}

#[derive(Serialize)]
struct JsonSummary {
    failures: usize,
    warnings: usize,
    passed: usize,
}

#[derive(Serialize)]
struct JsonResult {
    id: &'static str,
    control: &'static str,
    level: Level,
    status: Status,
    #[serde(skip_serializing_if = "Option::is_none")]
    detail: Option<&'static str>,
}

pub fn json(report: &Report) -> Result<String> {
    let doc = JsonReport {
        check: "gke",
        cluster: JsonCluster {
            name: &report.name,
            location: &report.location,
        },
        summary: JsonSummary {
            failures: report.failures(),
            warnings: report.warnings(),
            passed: report.passed(),
        },
        results: report
            .outcomes
            .iter()
            .map(|o| JsonResult {
                id: o.rule.id,
                control: o.rule.control,
                level: o.rule.level,
                status: o.status,
                detail: (o.status != Status::Pass).then_some(o.rule.detail),
            })
            .collect(),
    };
    Ok(serde_json::to_string_pretty(&doc)? + "\n")
}

fn sarif_level(level: Level) -> &'static str {
    match level {
        Level::Fail => "error",
        Level::Warn => "warning",
    }
}

/// SARIF 2.1.0 log with one result per control that did not pass.
pub fn sarif(report: &Report, uri: Option<&str>) -> Result<String> {
    let rules: Vec<Value> = RULES
        .iter()
        .map(|rule| {
            json!({
                "id": rule.id,
                "name": rule.control,
                "shortDescription": { "text": rule.control },
                "fullDescription": { "text": rule.why },
                "help": { "text": rule.detail },
                "helpUri": HELP_URI,
                "defaultConfiguration": { "level": sarif_level(rule.level) },
            })
        })
        .collect();

    let results: Vec<Value> = report
        .outcomes
        .iter()
        .filter(|o| o.status != Status::Pass)
        .map(|o| {
            let index = RULES
                .iter()
                .position(|r| r.id == o.rule.id)
                .unwrap_or_default();
            let mut location = json!({
                "logicalLocations": [{
                    "name": report.name,
                    "fullyQualifiedName": format!("{}/{}", report.location, report.name),
                    "kind": "resource",
                }],
            });
            if let Some(uri) = uri {
                location["physicalLocation"] = json!({ "artifactLocation": { "uri": uri } });
            }
            json!({
                "ruleId": o.rule.id,
                "ruleIndex": index,
                "level": sarif_level(o.rule.level),
                "message": {
                    "text": format!(
                        "{} ({}/{}): {}",
                        o.rule.control, report.location, report.name, o.rule.detail
                    ),
                },
                "locations": [location],
            })
        })
        .collect();

    let log = json!({
        "$schema": SARIF_SCHEMA,
        "version": "2.1.0",
        "runs": [{
            "tool": {
                "driver": {
                    "name": "stb",
                    "semanticVersion": env!("CARGO_PKG_VERSION"),
                    "informationUri": INFORMATION_URI,
                    "rules": rules,
                },
            },
            "results": results,
        }],
    });
    Ok(serde_json::to_string_pretty(&log)? + "\n")
}
