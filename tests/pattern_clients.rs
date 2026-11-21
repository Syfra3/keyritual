use std::{fs, path::Path};

#[test]
fn linux_client_source_exposes_pattern_controls_and_protocol() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let source = fs::read_to_string(root.join("Keyritual.qml")).unwrap();
    for required in [
        "Targeted practice",
        "Enable pattern collection",
        "Disable pattern collection",
        "Clear pattern data",
        "pattern_practice",
        "pattern_fallback",
    ] {
        assert!(
            source.contains(required),
            "Keyritual.qml is missing {required:?}"
        );
    }
}
