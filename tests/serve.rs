use std::{
    io::Write,
    process::{Command, Stdio},
};

#[test]
fn blank_lines_are_ignored_but_invalid_nonblank_json_is_reported() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_keyritual-core"))
        .arg("serve")
        .env(
            "XDG_STATE_HOME",
            std::env::temp_dir().join(format!("keyritual-empty-state-{}", std::process::id())),
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start Rust engine");

    let mut stdin = child.stdin.take().expect("engine stdin");
    stdin
        .write_all(b"\n{\"id\":1,\"type\":\"start\",\"mode\":\"words\",\"limit\":10,\"strict\":false}\n  \t \nnot-json\n")
        .expect("write requests");
    drop(stdin);

    let result = child.wait_with_output().expect("wait for engine");
    assert!(result.status.success());
    let lines: Vec<_> = result
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .collect();
    assert_eq!(lines.len(), 2, "blank lines must not produce replies");
    let state: serde_json::Value = serde_json::from_slice(lines[0]).unwrap();
    assert_eq!(state["phase"], "ready");
    let error: serde_json::Value = serde_json::from_slice(lines[1]).unwrap();
    assert_eq!(error["message"], "invalid JSON");
}
