use std::io::{self, BufRead, Write};

use fast_build_runner_daemon::{handle_request, DaemonRequest, DaemonResponse};

fn main() {
    if let Err(error) = run() {
        let response = DaemonResponse::Error {
            id: None,
            message: format!("{error:#}"),
        };
        let _ = println!(
            "{}",
            serde_json::to_string(&response).unwrap_or_else(|_| {
                r#"{"kind":"error","id":null,"message":"failed to serialize daemon error"}"#
                    .to_string()
            })
        );
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();

    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<DaemonRequest>(&line) {
            Ok(request) => handle_request(request),
            Err(error) => DaemonResponse::Error {
                id: None,
                message: format!("Failed to parse daemon request: {error}"),
            },
        };

        serde_json::to_writer(&mut stdout, &response)?;
        writeln!(&mut stdout)?;
        stdout.flush()?;
    }

    Ok(())
}
