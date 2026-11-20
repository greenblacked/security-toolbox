//! Reading check input from a file or stdin.

use std::fs;
use std::io::{self, IsTerminal, Read};
use std::path::Path;

use anyhow::{Context, Result, bail};
use serde_json::Value;

/// Parsed input plus where it came from.
pub struct Input {
    pub value: Value,
    /// Relative URI of the input file for SARIF locations; `None` for stdin.
    pub uri: Option<String>,
}

/// Reads one JSON document from `file`, or from stdin when `file` is `None` or `-`.
pub fn read_json(file: Option<&Path>) -> Result<Input> {
    let (bytes, source, uri) = match file {
        Some(path) if path != Path::new("-") => {
            let bytes =
                fs::read(path).with_context(|| format!("cannot read {}", path.display()))?;
            (bytes, path.display().to_string(), Some(to_uri(path)))
        }
        _ => {
            let mut stdin = io::stdin().lock();
            if file.is_none() && stdin.is_terminal() {
                bail!("no input: pass --file PATH or pipe JSON on stdin");
            }
            let mut bytes = Vec::new();
            stdin.read_to_end(&mut bytes).context("cannot read stdin")?;
            (bytes, "stdin".to_owned(), None)
        }
    };
    let value: Value =
        serde_json::from_slice(&bytes).with_context(|| format!("malformed JSON in {source}"))?;
    Ok(Input { value, uri })
}

/// Percent-encodes a path into a URI reference, keeping `/` separators.
fn to_uri(path: &Path) -> String {
    let raw = path.to_string_lossy().replace('\\', "/");
    let mut out = String::with_capacity(raw.len());
    for byte in raw.bytes() {
        if byte.is_ascii_alphanumeric() || b"-._~/".contains(&byte) {
            out.push(char::from(byte));
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}
