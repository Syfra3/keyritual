use std::{
    fs,
    io::Write,
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

fn run_engine(
    config: &std::path::Path,
    state: &std::path::Path,
    input: &str,
) -> Vec<serde_json::Value> {
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env("XDG_CONFIG_HOME", config)
        .env("XDG_STATE_HOME", state)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success());
    result
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_slice(line).unwrap())
        .collect()
}

#[test]
fn command_chord_persists_without_touching_history() {
    let dir = std::env::temp_dir().join(format!(
        "keyritual-chord-ipc-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let config = dir.join("config");
    let state = dir.join("state");
    let replies = run_engine(
        &config,
        &state,
        "{\"id\":1,\"type\":\"get_preferences\"}\n{\"id\":2,\"type\":\"set_command_key\",\"key\":\"space\"}\n{\"id\":3,\"type\":\"set_command_key\",\"key\":\"escape\"}\n{\"id\":4,\"type\":\"get_preferences\"}\n",
    );
    assert_eq!(replies[0]["command_key"], "m");
    assert_eq!(replies[0]["global_shortcut_prompted"], false);
    assert_eq!(replies[1]["command_key"], "space");
    assert_eq!(replies[2]["type"], "error");
    assert_eq!(replies[3]["command_key"], "space");
    assert_eq!(
        run_engine(&config, &state, "{\"id\":5,\"type\":\"get_preferences\"}\n")[0]["command_key"],
        "space"
    );
    let prompt = run_engine(
        &config,
        &state,
        "{\"id\":7,\"type\":\"set_shortcut_prompted\",\"value\":true}\n{\"id\":8,\"type\":\"get_preferences\"}\n",
    );
    assert_eq!(prompt[0]["global_shortcut_prompted"], true);
    assert_eq!(prompt[1]["global_shortcut_prompted"], true);
    assert_eq!(
        run_engine(&config, &state, "{\"id\":9,\"type\":\"get_preferences\"}\n")[0]["global_shortcut_prompted"],
        true
    );
    assert!(!state.join("keyritual/history.json").exists());
    fs::write(config.join("keyritual/preferences.json"), b"{broken").unwrap();
    let fallback = run_engine(&config, &state, "{\"id\":6,\"type\":\"get_preferences\"}\n");
    assert_eq!(fallback[0]["command_key"], "m");
    assert_eq!(fallback[0]["warning"], "Invalid preferences; using Ctrl+M");
    fs::remove_dir_all(dir).unwrap();
}
