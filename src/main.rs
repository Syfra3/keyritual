use keyritual_core::{
    engine::{Command as Input, Phase, Session},
    preferences::Preferences,
    storage::{PatternStore, Store},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    error::Error,
    io::{self, BufRead, Write},
    path::PathBuf,
    process::Command,
    time::Instant,
};

const PLUGIN_ID: &str = "io.github.syfra3.keyritual";

#[derive(Deserialize)]
struct Request {
    #[serde(default)]
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
    let mut server = Server::load()?;
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    for line in stdin.lock().lines() {
        if let Some(response) = server.handle_line(&line?) {
            writeln!(stdout, "{response}")?;
            stdout.flush()?;
        }
    }
    Ok(())
}

struct Server {
    history_path: PathBuf,
    pattern_path: PathBuf,
    preferences_path: PathBuf,
    store: Store,
    patterns: PatternStore,
    preferences: Preferences,
    preferences_invalid: bool,
    session: Option<Session>,
    session_clear_generation: u64,
}

fn error(id: u64, message: impl std::fmt::Display) -> Value {
    json!({"type":"error", "id":id, "message":message.to_string()})
}

fn parse_request(line: &str) -> Result<Option<Request>, Value> {
    if line.trim().is_empty() {
        return Ok(None);
    }
    if line.len() > 4096 {
        return Err(error(0, "request too large"));
    }
    let value: Value = serde_json::from_str(line).map_err(|_| error(0, "invalid JSON"))?;
    let id = value.get("id").and_then(Value::as_u64).unwrap_or(0);
    serde_json::from_value(value)
        .map(Some)
        .map_err(|e| error(id, e))
}

impl Server {
    fn load() -> Result<Self, Box<dyn Error>> {
        let history_path = Store::state_path()?;
        let pattern_path = history_path.with_file_name("patterns.json");
        let preferences_path = Preferences::path()?;
        let store = Store::load(&history_path)?;
        let patterns = PatternStore::load(&pattern_path)?;
        let (preferences, preferences_invalid) = Preferences::load(&preferences_path);
        Ok(Self {
            history_path,
            pattern_path,
            preferences_path,
            store,
            patterns,
            preferences,
            preferences_invalid,
            session: None,
            session_clear_generation: 0,
        })
    }

    fn handle_line(&mut self, line: &str) -> Option<Value> {
        match parse_request(line) {
            Ok(Some(request)) => Some(self.handle_request(request)),
            Ok(None) => None,
            Err(response) => Some(response),
        }
    }

    fn synchronize_patterns(&mut self, command: &Input) -> io::Result<Option<std::fs::File>> {
        let create = matches!(
            command,
            Input::SetPatternPractice { .. }
                | Input::ClearPatternPractice
                | Input::Key { .. }
                | Input::Backspace
                | Input::Tick
        );
        let guard = PatternStore::lock(&self.pattern_path, create)?;
        self.patterns = if guard.is_some() {
            PatternStore::load(&self.pattern_path)?
        } else {
            PatternStore::default()
        };
        if let Some(active) = &mut self.session {
            active.pattern_collection = self.patterns.enabled;
            if !self.patterns.enabled
                || self.session_clear_generation != self.patterns.clear_generation
            {
                active.pattern_observations = Default::default();
            }
        }
        self.session_clear_generation = self.patterns.clear_generation;
        Ok(guard)
    }

    fn handle_request(&mut self, request: Request) -> Value {
        // Keep the guard through observation, consent changes, and persistence.
        let _guard = match self.synchronize_patterns(&request.command) {
            Ok(guard) => guard,
            Err(_) => return self.pattern_access_error(&request),
        };
        self.dispatch(request)
    }

    fn pattern_access_error(&self, request: &Request) -> Value {
        json!({"type":"error", "id":request.id, "code":"pattern_state_unavailable",
            "message":"Could not access pattern practice settings"})
    }

    fn dispatch(&mut self, request: Request) -> Value {
        let id = request.id;
        match request.command {
            Input::GetPatternPractice => self.pattern_response(id),
            Input::SetPatternPractice { enabled } => self.set_pattern_enabled(id, enabled),
            Input::ClearPatternPractice => self.clear_patterns(id),
            Input::GetPreferences => self.preferences_response(id, false),
            Input::SetCommandKey { key } => self.set_command_key(id, key),
            Input::SetShortcutPrompted { value } => self.set_shortcut_prompted(id, value),
            Input::History => self.history_response(id),
            command @ Input::Start { .. } => self.start_session(id, command),
            command => self.advance_session(id, command),
        }
    }

    fn pattern_response(&self, id: u64) -> Value {
        json!({"type":"pattern_practice", "id":id, "enabled":self.patterns.enabled})
    }

    fn set_pattern_enabled(&mut self, id: u64, enabled: bool) -> Value {
        let mut next = self.patterns.clone();
        next.enabled = enabled;
        self.save_pattern_change(id, next, false)
    }

    fn clear_patterns(&mut self, id: u64) -> Value {
        let mut next = self.patterns.clone();
        let Some(generation) = next.clear_generation.checked_add(1) else {
            return error(id, "Could not clear pattern practice settings");
        };
        next.clear_generation = generation;
        next.patterns = Default::default();
        self.save_pattern_change(id, next, true)
    }

    fn save_pattern_change(&mut self, id: u64, next: PatternStore, clear: bool) -> Value {
        if next.save(&self.pattern_path).is_err() {
            return error(id, "Could not save pattern practice settings");
        }
        self.patterns = next;
        self.session_clear_generation = self.patterns.clear_generation;
        if let Some(active) = &mut self.session {
            active.pattern_collection = self.patterns.enabled;
            if clear {
                active.pattern_observations = Default::default();
            }
        }
        self.pattern_response(id)
    }

    fn preferences_response(&self, id: u64, changed: bool) -> Value {
        json!({"type":"preferences", "id":id, "command_key":self.preferences.command_key,
            "global_shortcut_prompted":self.preferences.global_shortcut_prompted,
            "warning":if self.preferences_invalid && !changed { "Invalid preferences; using Ctrl+M" } else { "" }})
    }

    fn history_response(&mut self, id: u64) -> Value {
        match Store::load(&self.history_path) {
            Ok(store) => {
                self.store = store;
                json!({"type":"history", "id":id, "records":self.store.recent()})
            }
            Err(_) => error(id, "Could not load session history"),
        }
    }

    fn set_command_key(&mut self, id: u64, key: String) -> Value {
        if !Preferences::valid_key(&key) {
            return error(id, "Shortcut must be Ctrl+letter or Ctrl+Space");
        }
        let next = Preferences {
            command_key: key,
            global_shortcut_prompted: self.preferences.global_shortcut_prompted,
        };
        self.save_preferences(id, next, "Could not save shortcut settings")
    }

    fn set_shortcut_prompted(&mut self, id: u64, value: bool) -> Value {
        let next = Preferences {
            command_key: self.preferences.command_key.clone(),
            global_shortcut_prompted: value,
        };
        self.save_preferences(id, next, "Could not save global shortcut decision")
    }

    fn save_preferences(&mut self, id: u64, next: Preferences, message: &str) -> Value {
        if next.save(&self.preferences_path).is_err() {
            return error(id, message);
        }
        self.preferences = next;
        self.preferences_invalid = false;
        self.preferences_response(id, true)
    }

    fn start_session(&mut self, id: u64, command: Input) -> Value {
        let Input::Start {
            mode,
            limit,
            strict,
            punctuation,
            numbers,
            targeted,
        } = command
        else {
            unreachable!()
        };
        if targeted && !self.patterns.enabled {
            return error(id, "Enable pattern collection before targeted practice");
        }
        let mut session = match Session::random(mode, limit, strict, punctuation, numbers) {
            Ok(session) => session,
            Err(message) => return error(id, message),
        };
        session.pattern_collection = self.patterns.enabled;
        if targeted {
            session.target_patterns(&self.patterns.patterns);
        }
        self.session = Some(session);
        self.snapshot(id, Instant::now())
    }

    fn advance_session(&mut self, id: u64, command: Input) -> Value {
        let now = Instant::now();
        let Some(active) = &mut self.session else {
            return error(id, "start a session first");
        };
        active.apply(command, now);
        if active.newly_finished
            && let Err(message) = self.record_session(now)
        {
            return error(id, message);
        }
        self.snapshot(id, now)
    }

    fn record_session(&mut self, now: Instant) -> Result<(), &'static str> {
        let active = self.session.as_ref().expect("active session");
        let mut next =
            Store::load(&self.history_path).map_err(|_| "Could not load session history")?;
        next.record(active, now, &self.history_path)
            .map_err(|_| "Could not save session history")?;
        self.store = next;
        if !active.pattern_observations.is_empty() {
            let mut patterns = self.patterns.clone();
            patterns.patterns.merge(&active.pattern_observations);
            patterns
                .save(&self.pattern_path)
                .map_err(|_| "Could not save pattern statistics")?;
            self.patterns = patterns;
        }
        Ok(())
    }

    fn snapshot(&self, id: u64, now: Instant) -> Value {
        let active = self.session.as_ref().expect("active session");
        let best = self.store.best(
            active.mode,
            active.limit,
            active.strict,
            active.punctuation,
            active.numbers,
        );
        let mut snapshot = active.snapshot(id, now, best);
        if active.phase == Phase::Finished {
            if let Some(previous) = self.store.previous_comparable(active) {
                snapshot.previous_wpm = Some(previous.wpm);
                snapshot.previous_accuracy = Some(previous.accuracy);
                snapshot.previous_mistakes = previous.mistakes;
            }
            let (wpm, errors) = self.store.prior_average(active);
            snapshot.prior_average_wpm = wpm;
            snapshot.prior_average_errors = errors;
        }
        serde_json::to_value(snapshot).expect("snapshot serialization")
    }
}
