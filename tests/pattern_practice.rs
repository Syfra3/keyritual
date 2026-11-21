use serde_json::{Value, json};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

fn state_root() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!("keyritual-pattern-{}-{nonce}", std::process::id()))
}

fn requests(root: &Path, input: &[Value]) -> Vec<Value> {
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    for request in input {
        writeln!(stdin, "{request}").unwrap();
    }
    drop(stdin);
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success(), "engine exited unsuccessfully");
    result
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_slice(line).unwrap())
        .collect()
}

#[test]
fn consent_is_explicit_persistent_and_clear_does_not_disable_it() {
    let root = state_root();
    let responses = requests(
        &root,
        &[
            json!({"id": 1, "type": "get_pattern_practice"}),
            json!({"id": 2, "type": "set_pattern_practice", "enabled": true}),
            json!({"id": 3, "type": "clear_pattern_practice"}),
        ],
    );
    assert_eq!(
        responses[0],
        json!({"type":"pattern_practice", "id":1, "enabled":false})
    );
    assert_eq!(
        responses[1],
        json!({"type":"pattern_practice", "id":2, "enabled":true})
    );
    assert_eq!(
        responses[2],
        json!({"type":"pattern_practice", "id":3, "enabled":true})
    );
    let responses = requests(
        &root,
        &[
            json!({"id": 4, "type": "get_pattern_practice"}),
            json!({"id": 5, "type": "set_pattern_practice", "enabled": false}),
        ],
    );
    assert_eq!(responses[0]["enabled"], true);
    assert_eq!(responses[1]["enabled"], false);
    assert_eq!(
        requests(&root, &[json!({"id": 6, "type": "get_pattern_practice"})])[0]["enabled"],
        false
    );
}

#[test]
fn targeted_practice_requires_consent_and_falls_back_without_data() {
    let root = state_root();
    let responses = requests(
        &root,
        &[
            json!({"id": 1, "type": "start", "mode": "words", "limit": 10, "strict": false, "targeted": true}),
            json!({"id": 2, "type": "set_pattern_practice", "enabled": true}),
            json!({"id": 3, "type": "start", "mode": "words", "limit": 10, "strict": false, "targeted": true}),
            json!({"id": 4, "type": "start", "mode": "words", "limit": 10, "strict": false}),
        ],
    );
    assert_eq!(responses[0]["type"], "error");
    assert_eq!(responses[2]["phase"], "ready");
    assert_eq!(responses[2]["targeted"], true);
    assert_eq!(responses[2]["pattern_fallback"], true);
    assert_eq!(responses[3]["phase"], "ready");
    assert_eq!(responses[3]["targeted"], false);
}

#[test]
fn legacy_history_survives_enabling_and_clearing_pattern_data() {
    let root = state_root();
    let directory = root.join("state/keyritual");
    fs::create_dir_all(&directory).unwrap();
    fs::write(directory.join("history.json"), r#"{"history":[{"mode":"time","limit":30,"strict":false,"wpm":42,"accuracy":98.0,"timestamp":100}]}"#).unwrap();

    let responses = requests(
        &root,
        &[
            json!({"id": 1, "type": "get_pattern_practice"}),
            json!({"id": 2, "type": "set_pattern_practice", "enabled": true}),
            json!({"id": 3, "type": "clear_pattern_practice"}),
            json!({"id": 4, "type": "history"}),
        ],
    );
    assert_eq!(responses[0]["enabled"], false);
    assert_eq!(responses[2]["enabled"], true);
    assert_eq!(responses[3]["records"].as_array().unwrap().len(), 1);
    assert_eq!(responses[3]["records"][0]["wpm"], 42);
    let restarted = requests(&root, &[json!({"id": 5, "type": "history"})]);
    assert_eq!(restarted[0]["records"][0]["wpm"], 42);
}

#[test]
fn invalid_consent_value_cannot_enable_collection() {
    let root = state_root();
    let responses = requests(
        &root,
        &[
            json!({"id": 1, "type": "set_pattern_practice", "enabled": "yes"}),
            json!({"id": 2, "type": "get_pattern_practice"}),
        ],
    );
    assert_eq!(responses[0]["type"], "error");
    assert_eq!(responses[1]["type"], "pattern_practice");
    assert_eq!(responses[1]["enabled"], false);
}

#[test]
fn failed_consent_save_reports_error_and_leaves_collection_disabled() {
    let root = state_root();
    fs::create_dir_all(&root).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    writeln!(stdin, "{}", json!({"id":1,"type":"get_pattern_practice"})).unwrap();
    let mut line = String::new();
    stdout.read_line(&mut line).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap()["enabled"],
        false
    );

    // Replacing the state directory with a regular file reliably blocks saving,
    // including when tests run with elevated permissions.
    fs::write(root.join("state"), b"not a directory").unwrap();
    writeln!(
        stdin,
        "{}",
        json!({"id":2,"type":"set_pattern_practice","enabled":true})
    )
    .unwrap();
    line.clear();
    stdout.read_line(&mut line).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap()["type"],
        "error"
    );
    writeln!(stdin, "{}", json!({"id":3,"type":"get_pattern_practice"})).unwrap();
    line.clear();
    stdout.read_line(&mut line).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap()["type"],
        "error"
    );
    fs::remove_file(root.join("state")).unwrap();
    writeln!(stdin, "{}", json!({"id":4,"type":"get_pattern_practice"})).unwrap();
    line.clear();
    stdout.read_line(&mut line).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap()["enabled"],
        false
    );
    drop(stdin);
    assert!(child.wait().unwrap().success());
}

#[test]
fn completed_practice_teaches_across_restart_and_clear_preserves_history() {
    let root = state_root();
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut send = |request: Value| -> Value {
        writeln!(stdin, "{request}").unwrap();
        let mut line = String::new();
        stdout.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };
    assert_eq!(
        send(json!({"id":1,"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let start = send(json!({"id":2,"type":"start","mode":"words","limit":10,"strict":false}));
    let prompt = start["prompt"].as_str().unwrap().to_owned();
    let first = prompt.chars().next().unwrap();
    let incorrect = if first == 'x' { 'z' } else { 'x' };
    for _ in 0..5 {
        send(json!({"type":"key","text":incorrect.to_string()}));
        send(json!({"type":"backspace"}));
    }
    let mut last = Value::Null;
    for character in prompt.chars() {
        last = send(json!({"type":"key","text":character.to_string()}));
    }
    assert_eq!(last["phase"], "finished");
    drop(send);
    drop(stdin);
    assert!(child.wait().unwrap().success());

    let responses = requests(
        &root,
        &[
            json!({"id":3,"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}),
            json!({"id":4,"type":"clear_pattern_practice"}),
            json!({"id":5,"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}),
            json!({"id":6,"type":"history"}),
        ],
    );
    assert_eq!(responses[0]["pattern_fallback"], false);
    assert_eq!(responses[1]["enabled"], true);
    assert_eq!(responses[2]["pattern_fallback"], true);
    assert_eq!(responses[3]["records"].as_array().unwrap().len(), 1);
}

#[test]
fn disabling_during_session_prevents_later_attempts_from_being_collected() {
    let root = state_root();
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut send = |request: Value| -> Value {
        writeln!(stdin, "{request}").unwrap();
        let mut line = String::new();
        stdout.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };
    assert_eq!(
        send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let start = send(json!({"type":"start","mode":"words","limit":10,"strict":false}));
    let prompt = start["prompt"].as_str().unwrap().to_owned();
    assert_eq!(
        send(json!({"type":"set_pattern_practice","enabled":false}))["enabled"],
        false
    );
    let first = prompt.chars().next().unwrap();
    let incorrect = if first == 'x' { 'z' } else { 'x' };
    for _ in 0..5 {
        send(json!({"type":"key","text":incorrect.to_string()}));
        send(json!({"type":"backspace"}));
    }
    for character in prompt.chars() {
        send(json!({"type":"key","text":character.to_string()}));
    }
    drop(send);
    drop(stdin);
    assert!(child.wait().unwrap().success());
    let responses = requests(
        &root,
        &[
            json!({"type":"set_pattern_practice","enabled":true}),
            json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}),
        ],
    );
    assert_eq!(responses[1]["pattern_fallback"], true);
}

#[test]
fn strict_failed_sessions_do_not_commit_partial_observations() {
    let root = state_root();
    let mut commands = vec![json!({"type":"set_pattern_practice","enabled":true})];
    for _ in 0..5 {
        commands.push(json!({"type":"start","mode":"words","limit":10,"strict":true}));
        commands.push(json!({"type":"key","text":"!"}));
    }
    commands.push(json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}));
    commands.push(json!({"type":"history"}));
    let replies = requests(&root, &commands);
    for reply in replies.iter().skip(2).take(9).step_by(2) {
        assert_eq!(reply["phase"], "failed");
    }
    assert_eq!(replies[11]["pattern_fallback"], true);
    assert_eq!(replies[12]["records"].as_array().unwrap().len(), 0);
}

#[test]
fn failed_clear_reports_error_and_keeps_saved_learning() {
    let root = state_root();
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = BufReader::new(child.stdout.take().unwrap());
    let mut send = |request: Value| -> Value {
        writeln!(stdin, "{request}").unwrap();
        let mut line = String::new();
        stdout.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };
    assert_eq!(
        send(json!({"type":"set_pattern_practice","enabled":true}))["enabled"],
        true
    );
    let prompt = send(json!({"type":"start","mode":"words","limit":10,"strict":false}))["prompt"]
        .as_str()
        .unwrap()
        .to_owned();
    let incorrect = if prompt.starts_with('x') { 'z' } else { 'x' };
    for _ in 0..5 {
        send(json!({"type":"key","text":incorrect.to_string()}));
        send(json!({"type":"backspace"}));
    }
    for character in prompt.chars() {
        send(json!({"type":"key","text":character.to_string()}));
    }
    fs::rename(root.join("state"), root.join("state-backup")).unwrap();
    fs::write(root.join("state"), b"not a directory").unwrap();
    assert_eq!(
        send(json!({"type":"clear_pattern_practice"}))["type"],
        "error"
    );
    assert_eq!(
        send(json!({"type":"get_pattern_practice"}))["type"],
        "error"
    );
    fs::remove_file(root.join("state")).unwrap();
    fs::rename(root.join("state-backup"), root.join("state")).unwrap();
    assert_eq!(
        send(json!({"type":"get_pattern_practice"}))["enabled"],
        true
    );
    assert_eq!(
        send(json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true}))["pattern_fallback"],
        false
    );
    drop(send);
    drop(stdin);
    assert!(child.wait().unwrap().success());
    assert_eq!(
        requests(
            &root,
            &[json!({"type":"start","mode":"words","limit":10,"strict":false,"targeted":true})]
        )[0]["pattern_fallback"],
        false
    );
}
