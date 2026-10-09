use keyritual_core::{
    engine::{Command as Input, Phase, Session},
    storage::Store,
};
use serde::Deserialize;
use serde_json::json;
use std::{
    error::Error,
    io::{self, BufRead, Write},
    process::Command,
    time::Instant,
};

const PLUGIN_ID: &str = "io.github.syfra3.keyritual";

#[derive(Deserialize)]
struct Request {
    id: u64,
    #[serde(flatten)]
    command: Input,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("keyritual: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    match std::env::args().nth(1).as_deref() {
        Some("serve") => serve(),
        Some("--version") => {
            println!("keyritual-core {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("launch") => {
            let status = Command::new("omarchy-shell")
                .args(["shell", "toggle", PLUGIN_ID, "{}"])
                .status()
                .map_err(|error| format!("could not launch Omarchy Quattro shell: {error}"))?;
            if !status.success() {
                return Err(format!("omarchy-shell failed ({status}); Keyritual requires Omarchy Quattro / 4.x and an enabled plugin").into());
            }
            Ok(())
        }
        _ => {
            eprintln!("Usage: keyritual-core <serve|launch|--version>");
            Err("provide serve or launch".into())
        }
    }
}

fn serve() -> Result<(), Box<dyn Error>> {
    let path = Store::state_path()?;
    let mut store = Store::load(&path)?;
    let mut session: Option<Session> = None;
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if line.len() > 4096 {
            writeln!(
                stdout,
                "{}",
                json!({ "type": "error", "id": 0, "message": "request too large" })
            )?;
            stdout.flush()?;
            continue;
        }
        let value: serde_json::Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            Err(_) => {
                writeln!(
                    stdout,
                    "{}",
                    json!({ "type": "error", "id": 0, "message": "invalid JSON" })
                )?;
                stdout.flush()?;
                continue;
            }
        };
        let id = value.get("id").and_then(|id| id.as_u64()).unwrap_or(0);
        let request: Request = match serde_json::from_value(value) {
            Ok(request) => request,
            Err(error) => {
                writeln!(
                    stdout,
                    "{}",
                    json!({ "type": "error", "id": id, "message": error.to_string() })
                )?;
                stdout.flush()?;
                continue;
            }
        };
        if matches!(request.command, Input::History) {
            writeln!(
                stdout,
                "{}",
                json!({ "type": "history", "id": request.id, "records": store.recent() })
            )?;
            stdout.flush()?;
            continue;
        }
        let now = Instant::now();
        if let Input::Start {
            mode,
            limit,
            strict,
            punctuation,
            numbers,
        } = request.command
        {
            match Session::random(mode, limit, strict, punctuation, numbers) {
                Ok(new_session) => session = Some(new_session),
                Err(error) => {
                    writeln!(
                        stdout,
                        "{}",
                        json!({ "type": "error", "id": request.id, "message": error })
                    )?;
                    stdout.flush()?;
                    continue;
                }
            }
        } else if let Some(active) = session.as_mut() {
            active.apply(request.command, now);
            if active.newly_finished {
                store.record(active, now, &path)?;
            }
        } else {
            writeln!(
                stdout,
                "{}",
                json!({ "type": "error", "id": request.id, "message": "start a session first" })
            )?;
            stdout.flush()?;
            continue;
        }
        if let Some(active) = &session {
            let best = store.best(
                active.mode,
                active.limit,
                active.strict,
                active.punctuation,
                active.numbers,
            );
            let mut snapshot = active.snapshot(request.id, now, best);
            if active.phase == Phase::Finished
                && let Some(previous) = store.previous_comparable(active)
            {
                snapshot.previous_wpm = Some(previous.wpm);
                snapshot.previous_accuracy = Some(previous.accuracy);
                snapshot.previous_mistakes = previous.mistakes;
            }
            if active.phase == Phase::Finished {
                let (wpm, errors) = store.prior_average(active);
                snapshot.prior_average_wpm = wpm;
                snapshot.prior_average_errors = errors;
            }
            writeln!(stdout, "{}", serde_json::to_string(&snapshot)?)?;
            stdout.flush()?;
        }
    }
    Ok(())
}
