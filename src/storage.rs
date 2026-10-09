use crate::engine::{Mode, Session};
use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Record {
    pub mode: Mode,
    pub limit: u32,
    pub strict: bool,
    #[serde(default)]
    pub punctuation: bool,
    #[serde(default)]
    pub numbers: bool,
    pub wpm: u32,
    pub accuracy: f64,
    #[serde(default)]
    pub mistakes: Option<u32>,
    #[serde(default)]
    pub raw_wpm: Option<u32>,
    #[serde(default)]
    pub consistency: Option<u32>,
    #[serde(default)]
    pub elapsed_ms: Option<u64>,
    pub timestamp: u64,
}

#[derive(Default, Serialize, Deserialize)]
pub struct Store {
    #[serde(default)]
    pub history: Vec<Record>,
}

impl Store {
    pub fn state_path() -> io::Result<PathBuf> {
        let base = std::env::var_os("XDG_STATE_HOME")
            .filter(|path| !path.is_empty())
            .map(PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state"))
            })
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::NotFound,
                    "HOME or XDG_STATE_HOME is required",
                )
            })?;
        Ok(base.join("keyritual/history.json"))
    }

    pub fn load(path: &Path) -> io::Result<Self> {
        match fs::read(path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(Self::default()),
            Err(error) => Err(error),
        }
    }

    pub fn best(
        &self,
        mode: Mode,
        limit: u32,
        strict: bool,
        punctuation: bool,
        numbers: bool,
    ) -> u32 {
        self.history
            .iter()
            .filter(|record| {
                record.mode == mode
                    && record.limit == limit
                    && record.strict == strict
                    && record.punctuation == punctuation
                    && record.numbers == numbers
            })
            .map(|record| record.wpm)
            .max()
            .unwrap_or(0)
    }

    /// Call after recording the current completed run; skip it to find the previous match.
    pub fn previous_comparable(&self, session: &Session) -> Option<&Record> {
        self.history
            .iter()
            .rev()
            .filter(|record| {
                record.mode == session.mode
                    && record.limit == session.limit
                    && record.strict == session.strict
                    && record.punctuation == session.punctuation
                    && record.numbers == session.numbers
            })
            .nth(1)
    }

    pub fn prior_average(&self, session: &Session) -> (Option<u32>, Option<f64>) {
        let prior: Vec<&Record> = self
            .history
            .iter()
            .rev()
            .filter(|record| {
                record.mode == session.mode
                    && record.limit == session.limit
                    && record.strict == session.strict
                    && record.punctuation == session.punctuation
                    && record.numbers == session.numbers
            })
            .skip(1)
            .take(5)
            .collect();
        if prior.is_empty() {
            return (None, None);
        }
        let avg_wpm = (prior
            .iter()
            .map(|record| u64::from(record.wpm))
            .sum::<u64>() as f64
            / prior.len() as f64)
            .round() as u32;
        let known: Vec<u32> = prior.iter().filter_map(|record| record.mistakes).collect();
        let avg_errors = if known.is_empty() {
            None
        } else {
            Some(known.iter().map(|v| f64::from(*v)).sum::<f64>() / known.len() as f64)
        };
        (Some(avg_wpm), avg_errors)
    }

    pub fn recent(&self) -> Vec<Record> {
        self.history.iter().rev().take(20).cloned().collect()
    }

    pub fn record(&mut self, session: &Session, now: Instant, path: &Path) -> io::Result<()> {
        let (wpm, raw_wpm, accuracy, mistakes) = session.score(now);
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        self.history.push(Record {
            mode: session.mode,
            limit: session.limit,
            strict: session.strict,
            punctuation: session.punctuation,
            numbers: session.numbers,
            wpm,
            accuracy,
            mistakes: Some(mistakes),
            raw_wpm: Some(raw_wpm),
            consistency: session.snapshot(0, now, 0).consistency,
            elapsed_ms: Some(session.snapshot(0, now, 0).elapsed_ms),
            timestamp,
        });
        if self.history.len() > 200 {
            self.history.drain(..self.history.len() - 200);
        }
        self.save(path)
    }

    fn save(&self, path: &Path) -> io::Result<()> {
        let parent = path
            .parent()
            .ok_or_else(|| io::Error::other("invalid state path"))?;
        fs::create_dir_all(parent)?;
        let temporary = parent.join(format!(".history-{}.tmp", std::process::id()));
        let json = serde_json::to_vec_pretty(self).map_err(io::Error::other)?;
        fs::write(&temporary, json)?;
        if let Err(error) = fs::rename(&temporary, path) {
            let _ = fs::remove_file(temporary);
            return Err(error);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::{Command, Phase};
    use std::time::Duration;

    #[test]
    fn previous_comparable_skips_current_and_other_settings() {
        let session = Session::new(Mode::Time, 30, false, false, false, 42).unwrap();
        let make = |wpm, limit| Record {
            mode: Mode::Time,
            limit,
            strict: false,
            punctuation: false,
            numbers: false,
            wpm,
            accuracy: 92.5,
            mistakes: None,
            raw_wpm: None,
            consistency: None,
            elapsed_ms: None,
            timestamp: 1,
        };
        let mut store = Store {
            history: vec![make(24, 30), make(99, 60), make(30, 30)],
        };
        assert_eq!(store.previous_comparable(&session).unwrap().wpm, 24);
        assert_eq!(store.prior_average(&session), (Some(24), None));
        assert_eq!(
            store.recent().iter().map(|r| r.wpm).collect::<Vec<_>>(),
            vec![30, 99, 24]
        );
        store.history.remove(0);
        assert!(store.previous_comparable(&session).is_none());
    }

    #[test]
    fn legacy_history_has_unknown_not_zero_error_counts() {
        let legacy = r#"{"history":[{"mode":"time","limit":30,"strict":false,"wpm":42,"accuracy":98.0,"timestamp":100}]}"#;
        let store: Store = serde_json::from_str(legacy).unwrap();
        assert_eq!(store.recent()[0].mistakes, None);
        assert_eq!(store.recent()[0].elapsed_ms, None);
        assert_eq!(store.recent()[0].wpm, 42);
    }

    #[test]
    fn saves_only_finished_runs_and_preserves_best_by_mode() {
        let directory = std::env::temp_dir().join(format!(
            "keyritual-store-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = directory.join("history.json");
        let mut store = Store::load(&path).unwrap();
        let mut session = Session::new(Mode::Words, 10, false, false, false, 42).unwrap();
        let t = Instant::now();
        for (index, text) in session.prompt.clone().chars().enumerate() {
            session.apply(
                Command::Key { text },
                t + Duration::from_millis(index as u64 * 50),
            );
        }
        assert_eq!(session.phase, Phase::Finished);
        store
            .record(&session, t + Duration::from_secs(5), &path)
            .unwrap();
        let loaded = Store::load(&path).unwrap();
        assert_eq!(loaded.history.len(), 1);
        assert_eq!(loaded.history[0].mistakes, Some(0));
        assert!(loaded.history[0].raw_wpm.is_some());
        assert!(loaded.history[0].elapsed_ms.is_some());
        assert!(loaded.best(Mode::Words, 10, false, false, false) > 0);
        assert_eq!(loaded.best(Mode::Words, 10, false, true, false), 0);
        assert_eq!(loaded.best(Mode::Time, 30, false, false, false), 0);
        fs::remove_dir_all(directory).unwrap();
    }
}
