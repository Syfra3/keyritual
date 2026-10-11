use serde::{Deserialize, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Preferences {
    pub command_key: String,
    #[serde(default)]
    pub global_shortcut_prompted: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            command_key: "m".into(),
            global_shortcut_prompted: false,
        }
    }
}

impl Preferences {
    pub fn path() -> io::Result<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .filter(|path| !path.is_empty())
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::NotFound,
                    "HOME or XDG_CONFIG_HOME is required",
                )
            })?;
        Ok(base.join("keyritual/preferences.json"))
    }

    pub fn valid_key(key: &str) -> bool {
        key == "space" || (key.len() == 1 && key.bytes().all(|c| c.is_ascii_lowercase()))
    }

    /// Invalid or unreadable user preferences fall back to the visible Ctrl+M default.
    pub fn load(path: &Path) -> (Self, bool) {
        match fs::read(path) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => (Self::default(), false),
            Ok(bytes) => match serde_json::from_slice::<Self>(&bytes) {
                Ok(value) if Self::valid_key(&value.command_key) => (value, false),
                _ => (Self::default(), true),
            },
            Err(_) => (Self::default(), true),
        }
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if !Self::valid_key(&self.command_key) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "unsupported command shortcut",
            ));
        }
        let parent = path
            .parent()
            .ok_or_else(|| io::Error::other("invalid preferences path"))?;
        fs::create_dir_all(parent)?;
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let temporary = parent.join(format!(".preferences-{}-{suffix}.tmp", std::process::id()));
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(&serde_json::to_vec_pretty(self).map_err(io::Error::other)?)?;
        file.sync_all()?;
        if let Err(error) = fs::rename(&temporary, path) {
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_valid_save_reload_and_reject_invalid() {
        let dir = std::env::temp_dir().join(format!(
            "keyritual-preferences-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = dir.join("config/keyritual/preferences.json");
        assert_eq!(Preferences::load(&path), (Preferences::default(), false));
        let custom = Preferences {
            command_key: "space".into(),
            global_shortcut_prompted: true,
        };
        custom.save(&path).unwrap();
        assert_eq!(Preferences::load(&path), (custom.clone(), false));
        let old: Preferences = serde_json::from_str(r#"{"command_key":"m"}"#).unwrap();
        assert!(!old.global_shortcut_prompted);
        assert!(!Preferences::valid_key("M"));
        assert!(!Preferences::valid_key("escape"));
        assert!(!Preferences::valid_key("shift+m"));
        assert!(
            Preferences {
                command_key: "escape".into(),
                global_shortcut_prompted: false,
            }
            .save(&path)
            .is_err()
        );
        assert_eq!(Preferences::load(&path), (custom, false));
        fs::write(&path, b"{broken").unwrap();
        assert_eq!(Preferences::load(&path), (Preferences::default(), true));
        fs::remove_dir_all(dir).unwrap();
    }
}
