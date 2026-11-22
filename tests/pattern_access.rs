use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

struct Engine {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl Engine {
    fn start(root: &Path) -> Self {
        let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
            .arg("serve")
            .env("XDG_STATE_HOME", root.join("state"))
            .env("XDG_CONFIG_HOME", root.join("config"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        Self {
            child,
            stdin,
            stdout,
        }
    }

    fn send(&mut self, message: Value) -> Value {
        writeln!(self.stdin, "{message}").unwrap();
        let mut line = String::new();
        assert_ne!(self.stdout.read_line(&mut line).unwrap(), 0);
        serde_json::from_str(&line).unwrap()
    }

    fn finish(self) {
        let Self {
            mut child,
            stdin,
            stdout,
        } = self;
        drop(stdin);
        drop(stdout);
        assert!(child.wait().unwrap().success());
    }
}

struct BlockedState {
    state: PathBuf,
    backup: PathBuf,
}

impl BlockedState {
    fn new(root: &Path) -> Self {
        let state = root.join("state");
        let backup = root.join("state-backup");
        fs::rename(&state, &backup).unwrap();
        if let Err(error) = fs::write(&state, b"not a directory") {
            fs::rename(&backup, &state).unwrap();
            panic!("could not block isolated state: {error}");
        }
        Self { state, backup }
    }
}

impl Drop for BlockedState {
    fn drop(&mut self) {
        if self.state.is_file() && self.backup.is_dir() {
            fs::remove_file(&self.state).unwrap();
            fs::rename(&self.backup, &self.state).unwrap();
        }
    }
}

#[test]
fn unavailable_shared_state_is_not_reported_as_stale_enabled_consent() {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "keyritual-pattern-access-{}-{nonce}",
        std::process::id()
    ));
    let mut first = Engine::start(&root);
    assert_eq!(
        first.send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let mut second = Engine::start(&root);
    assert_eq!(
        second.send(json!({"type":"get_pattern_practice"}))["enabled"],
        true
    );
    assert_eq!(
        first.send(json!({"type":"set_pattern_practice","enabled":false}))["enabled"],
        false
    );
    {
        let _blocked = BlockedState::new(&root);
        assert_eq!(
            second.send(json!({"type":"get_pattern_practice"}))["type"],
            "error"
        );
    }
    assert_eq!(
        second.send(json!({"type":"get_pattern_practice"}))["enabled"],
        false
    );
    first.finish();
    second.finish();
}
