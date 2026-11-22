use serde_json::{Value, json};
use std::{
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
        assert_ne!(
            self.stdout.read_line(&mut line).unwrap(),
            0,
            "engine output closed"
        );
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

fn state_root() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "keyritual-concurrency-{}-{nonce}",
        std::process::id()
    ))
}

#[test]
fn disabling_in_one_process_cannot_be_undone_by_another_running_session() {
    let root = state_root();
    let mut first = Engine::start(&root);
    assert_eq!(
        first.send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let mut second = Engine::start(&root);
    let session = second.send(json!({"type":"start","mode":"words","limit":10,"strict":false}));
    let prompt = session["prompt"].as_str().unwrap().to_owned();

    assert_eq!(
        first.send(json!({"type":"set_pattern_practice","enabled":false}))["enabled"],
        false
    );
    assert_eq!(
        second.send(json!({"type":"get_pattern_practice"}))["enabled"],
        false,
        "a running process must see the current consent decision"
    );

    let wrong = if prompt.starts_with('x') { 'z' } else { 'x' };
    for _ in 0..5 {
        second.send(json!({"type":"key","text":wrong.to_string()}));
        second.send(json!({"type":"backspace"}));
    }
    let mut state = Value::Null;
    for c in prompt.chars() {
        state = second.send(json!({"type":"key","text":c.to_string()}));
    }
    assert_eq!(state["phase"], "finished");
    second.finish();
    first.finish();

    let mut restarted = Engine::start(&root);
    assert_eq!(
        restarted.send(json!({"type":"get_pattern_practice"}))["enabled"],
        false,
        "a stale process must not restore enabled consent"
    );
    assert_eq!(
        restarted.send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let targeted = restarted
        .send(json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}));
    assert_eq!(
        targeted["pattern_fallback"], true,
        "attempts made after disabling must not have been collected"
    );
    restarted.finish();
}
