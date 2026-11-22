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

    fn start_words(&mut self) -> String {
        self.send(json!({"type":"start","mode":"words","limit":10,"strict":false}))["prompt"]
            .as_str()
            .unwrap()
            .to_owned()
    }

    fn complete(&mut self, prompt: &str) {
        let mut state = Value::Null;
        for character in prompt.chars() {
            state = self.send(json!({"type":"key","text":character.to_string()}));
        }
        assert_eq!(state["phase"], "finished");
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
        "keyritual-cross-process-{}-{nonce}",
        std::process::id()
    ))
}

#[test]
fn clearing_prevents_another_process_from_restoring_pre_clear_attempts() {
    let root = state_root();
    let mut first = Engine::start(&root);
    assert_eq!(
        first.send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let mut second = Engine::start(&root);
    let prompt = second.start_words();
    let wrong = if prompt.starts_with('x') { 'z' } else { 'x' };
    for _ in 0..5 {
        second.send(json!({"type":"key","text":wrong.to_string()}));
        second.send(json!({"type":"backspace"}));
    }
    assert_eq!(
        first.send(json!({"type":"clear_pattern_practice"}))["enabled"],
        true
    );
    second.complete(&prompt);
    second.finish();
    first.finish();

    let mut restarted = Engine::start(&root);
    let targeted = restarted
        .send(json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}));
    assert_eq!(
        targeted["pattern_fallback"], true,
        "pre-clear errors from another running session must not reappear"
    );
    restarted.finish();
}

#[test]
fn sessions_from_two_processes_preserve_both_history_records() {
    let root = state_root();
    let mut first = Engine::start(&root);
    let mut second = Engine::start(&root);
    let first_prompt = first.start_words();
    let second_prompt = second.start_words();
    first.complete(&first_prompt);
    second.complete(&second_prompt);
    first.finish();
    second.finish();

    let mut restarted = Engine::start(&root);
    let history = restarted.send(json!({"type":"history"}));
    assert_eq!(
        history["records"].as_array().unwrap().len(),
        2,
        "a later process must not overwrite another process's completed session"
    );
    restarted.finish();
}
