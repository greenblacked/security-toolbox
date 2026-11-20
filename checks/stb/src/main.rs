//! `stb`: read-only security checks that run against exported JSON.
//!
//! Nothing here calls a cloud API, runs a command or opens a network
//! connection. Each check reads what `gcloud` or `kubectl` already exported,
//! from a file or from stdin.
//!
//! Exit codes: 0 clean (warnings allowed), 1 at least one failure,
//! 2 usage or input error (including malformed JSON).
#![forbid(unsafe_code)]

mod gke;
mod input;
mod output;

use std::io::{self, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::Result;
use clap::{Args, Parser, Subcommand, ValueEnum};

const EXIT_FINDINGS: u8 = 1;
const EXIT_ERROR: u8 = 2;

#[derive(Parser)]
#[command(
    name = "stb",
    version,
    about = "Read-only security checks against exported cloud and Kubernetes JSON",
    after_help = "Exit codes: 0 clean (warnings allowed), 1 at least one failure, 2 usage or input error."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// GKE cluster hardening report from `gcloud container clusters describe --format=json`
    Gke(GkeArgs),
}

#[derive(Args)]
struct GkeArgs {
    /// Cluster JSON file. Use `-` or omit it to read stdin.
    #[arg(short, long, value_name = "PATH")]
    file: Option<PathBuf>,

    /// Output format
    #[arg(long, value_enum, default_value_t = Format::Text)]
    format: Format,
}

#[derive(Clone, Copy, ValueEnum)]
enum Format {
    Text,
    Json,
    Sarif,
}

fn main() -> ExitCode {
    // clap prints usage errors and exits 2; --help and --version exit 0.
    let cli = Cli::parse();
    match run(cli) {
        Ok(false) => ExitCode::SUCCESS,
        Ok(true) => ExitCode::from(EXIT_FINDINGS),
        Err(err) => {
            eprintln!("stb: error: {err:#}");
            ExitCode::from(EXIT_ERROR)
        }
    }
}

/// Runs the selected check. Returns whether any failure was found.
fn run(cli: Cli) -> Result<bool> {
    match cli.command {
        Command::Gke(args) => {
            let input = input::read_json(args.file.as_deref())?;
            let report = gke::evaluate(&input.value)?;
            let rendered = match args.format {
                Format::Text => output::text(&report),
                Format::Json => output::json(&report)?,
                Format::Sarif => output::sarif(&report, input.uri.as_deref())?,
            };
            let mut stdout = io::stdout().lock();
            stdout.write_all(rendered.as_bytes())?;
            stdout.flush()?;
            Ok(report.failures() > 0)
        }
    }
}
