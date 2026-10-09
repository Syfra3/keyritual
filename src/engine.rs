use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const WORDS: &[&str] = &[
    "about", "after", "again", "along", "always", "anchor", "answer", "around", "begin", "better",
    "bright", "build", "calm", "change", "clear", "close", "craft", "create", "daily", "dance",
    "deep", "detail", "dream", "early", "earth", "enough", "every", "field", "find", "first",
    "focus", "follow", "form", "fresh", "gentle", "give", "glow", "grow", "habit", "heart",
    "hello", "hold", "inside", "journey", "keep", "kind", "learn", "light", "little", "local",
    "make", "mind", "moment", "more", "move", "near", "never", "night", "note", "open", "pace",
    "path", "pause", "place", "quiet", "ready", "rest", "return", "rhythm", "rise", "round",
    "signal", "simple", "slow", "small", "space", "steady", "step", "story", "time", "today",
    "together", "touch", "under", "until", "warm", "water", "where", "whole", "window", "with",
    "wonder", "work", "world", "write",
];

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    Time,
    Words,
}

impl Mode {
    pub fn valid_limit(self, limit: u32) -> bool {
        match self {
            Self::Time => matches!(limit, 15 | 30 | 60),
            Self::Words => matches!(limit, 10 | 25 | 50),
        }
    }
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Ready,
    Running,
    Finished,
    Failed,
}

#[derive(Debug, Serialize)]
pub struct Snapshot {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub id: u64,
    pub phase: Phase,
    pub mode: Mode,
    pub limit: u32,
    pub strict: bool,
    pub punctuation: bool,
    pub numbers: bool,
    pub prompt: String,
    pub typed: String,
    pub elapsed_ms: u64,
    pub remaining_ms: u64,
    pub wpm: u32,
    pub raw_wpm: u32,
    pub accuracy: f64,
    pub best_wpm: u32,
    pub previous_wpm: Option<u32>,
    pub previous_accuracy: Option<f64>,
    pub previous_mistakes: Option<u32>,
    pub prior_average_wpm: Option<u32>,
    pub prior_average_errors: Option<f64>,
    pub mistakes: u32,
    pub pace_wpm: Vec<u32>,
    pub pace_seconds: Vec<u32>,
    pub consistency: Option<u32>,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Command {
    Start {
        mode: Mode,
        limit: u32,
        strict: bool,
        #[serde(default)]
        punctuation: bool,
        #[serde(default)]
        numbers: bool,
    },
    Key {
        text: char,
    },
    Backspace,
    Tick,
    History,
}

#[derive(Debug)]
pub struct Session {
    pub mode: Mode,
    pub limit: u32,
    pub strict: bool,
    pub punctuation: bool,
    pub numbers: bool,
    pub phase: Phase,
    pub prompt: String,
    pub typed: String,
    started: Option<Instant>,
    ended: Option<Instant>,
    attempts: u32,
    correct_attempts: u32,
    pub newly_finished: bool,
    pace_wpm: Vec<u32>,
    pace_seconds: Vec<u32>,
}

impl Session {
    pub fn new(
        mode: Mode,
        limit: u32,
        strict: bool,
        punctuation: bool,
        numbers: bool,
        seed: u64,
    ) -> Result<Self, &'static str> {
        if !mode.valid_limit(limit) {
            return Err("Select 15/30/60 seconds or 10/25/50 words");
        }
        let count = if mode == Mode::Time {
            260
        } else {
            limit as usize
        };
        let mut state = seed.max(1);
        let mut words = Vec::with_capacity(count);
        for index in 0..count {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            let word = if numbers && index % 9 == 3 {
                format!("{}", 10 + state % 990)
            } else {
                WORDS[(state as usize) % WORDS.len()].to_string()
            };
            let word = if punctuation && index % 7 == 5 {
                format!("{word},")
            } else if punctuation && index == count - 1 {
                format!("{word}.")
            } else {
                word
            };
            words.push(word);
        }
        Ok(Self {
            mode,
            limit,
            strict,
            punctuation,
            numbers,
            phase: Phase::Ready,
            prompt: words.join(" "),
            typed: String::new(),
            started: None,
            ended: None,
            attempts: 0,
            correct_attempts: 0,
            newly_finished: false,
            pace_wpm: Vec::new(),
            pace_seconds: Vec::new(),
        })
    }

    pub fn random(
        mode: Mode,
        limit: u32,
        strict: bool,
        punctuation: bool,
        numbers: bool,
    ) -> Result<Self, &'static str> {
        let seed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64;
        Self::new(
            mode,
            limit,
            strict,
            punctuation,
            numbers,
            seed ^ u64::from(std::process::id()),
        )
    }

    pub fn apply(&mut self, command: Command, now: Instant) {
        self.newly_finished = false;
        if matches!(self.phase, Phase::Finished | Phase::Failed) {
            return;
        }
        self.check_deadline(now);
        if self.phase == Phase::Finished {
            self.sample_pace(now);
            return;
        }

        match command {
            Command::Key { text } => {
                if !text.is_ascii_graphic() && text != ' ' {
                    return;
                }
                if self.typed.len() == self.prompt.len() {
                    return;
                }
                if self.started.is_none() {
                    self.started = Some(now);
                    self.phase = Phase::Running;
                }
                let expected = self.prompt.as_bytes()[self.typed.len()] as char;
                self.attempts += 1;
                if text == expected {
                    self.correct_attempts += 1;
                } else if self.strict {
                    self.phase = Phase::Failed;
                    self.ended = Some(now);
                    return;
                }
                self.typed.push(text);
                if self.typed.len() == self.prompt.len() {
                    self.complete(now);
                }
            }
            Command::Backspace => {
                self.typed.pop();
            }
            Command::Tick | Command::Start { .. } | Command::History => {}
        }
        self.sample_pace(now);
    }

    fn sample_pace(&mut self, now: Instant) {
        if self.started.is_none() {
            return;
        }
        let second = self.elapsed(now).as_secs();
        if second > 0 && second <= 600 && self.pace_seconds.last().copied() != Some(second as u32) {
            let (wpm, _, _, _) = self.score(now);
            self.pace_seconds.push(second as u32);
            self.pace_wpm.push(wpm);
        }
    }

    fn consistency(&self) -> Option<u32> {
        let positive: Vec<f64> = self
            .pace_wpm
            .iter()
            .copied()
            .filter(|wpm| *wpm > 0)
            .map(f64::from)
            .collect();
        if positive.len() < 2 {
            return None;
        }
        let mean = positive.iter().sum::<f64>() / positive.len() as f64;
        let variance = positive
            .iter()
            .map(|sample| (sample - mean).powi(2))
            .sum::<f64>()
            / positive.len() as f64;
        Some(
            ((1.0 - variance.sqrt() / mean) * 100.0)
                .clamp(0.0, 100.0)
                .round() as u32,
        )
    }

    fn complete(&mut self, now: Instant) {
        self.phase = Phase::Finished;
        self.ended = Some(now);
        self.newly_finished = true;
    }

    fn check_deadline(&mut self, now: Instant) {
        if self.phase == Phase::Running
            && self.mode == Mode::Time
            && self.elapsed(now) >= Duration::from_secs(self.limit.into())
        {
            self.complete(now);
        }
    }

    fn elapsed(&self, now: Instant) -> Duration {
        self.started
            .map(|start| self.ended.unwrap_or(now).saturating_duration_since(start))
            .unwrap_or_default()
    }

    pub fn score(&self, now: Instant) -> (u32, u32, f64, u32) {
        let minutes = self.elapsed(now).as_secs_f64() / 60.0;
        let correct = self
            .typed
            .bytes()
            .zip(self.prompt.bytes())
            .filter(|(actual, expected)| actual == expected)
            .count() as f64;
        let wpm = if minutes > 0.0 {
            ((correct / 5.0) / minutes).round() as u32
        } else {
            0
        };
        let raw_wpm = if minutes > 0.0 {
            ((f64::from(self.attempts) / 5.0) / minutes).round() as u32
        } else {
            0
        };
        let accuracy = if self.attempts > 0 {
            (f64::from(self.correct_attempts) / f64::from(self.attempts) * 1000.0).round() / 10.0
        } else {
            100.0
        };
        (
            wpm,
            raw_wpm,
            accuracy,
            self.attempts - self.correct_attempts,
        )
    }

    pub fn snapshot(&self, id: u64, now: Instant, best_wpm: u32) -> Snapshot {
        let elapsed = self.elapsed(now);
        let (wpm, raw_wpm, accuracy, mistakes) = self.score(now);
        Snapshot {
            kind: "state",
            id,
            phase: self.phase,
            mode: self.mode,
            limit: self.limit,
            strict: self.strict,
            punctuation: self.punctuation,
            numbers: self.numbers,
            prompt: self.prompt.clone(),
            typed: self.typed.clone(),
            elapsed_ms: elapsed.as_millis().min(u128::from(u64::MAX)) as u64,
            remaining_ms: if self.mode == Mode::Time {
                (u64::from(self.limit) * 1000).saturating_sub(elapsed.as_millis() as u64)
            } else {
                0
            },
            wpm,
            raw_wpm,
            accuracy,
            best_wpm,
            previous_wpm: None,
            previous_accuracy: None,
            previous_mistakes: None,
            prior_average_wpm: None,
            prior_average_errors: None,
            mistakes,
            pace_wpm: self.pace_wpm.clone(),
            pace_seconds: self.pace_seconds.clone(),
            consistency: self.consistency(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn time_starts_on_first_key_and_finishes_at_deadline() {
        let mut session = Session::new(Mode::Time, 15, false, false, false, 11).unwrap();
        let t = Instant::now();
        session.apply(Command::Tick, t + Duration::from_secs(30));
        assert_eq!(session.phase, Phase::Ready);
        let first = session.prompt.chars().next().unwrap();
        session.apply(Command::Key { text: first }, t);
        assert_eq!(session.phase, Phase::Running);
        session.apply(Command::Tick, t + Duration::from_secs(15));
        assert_eq!(session.phase, Phase::Finished);
        assert_eq!(session.snapshot(1, t, 0).remaining_ms, 0);
    }

    #[test]
    fn pace_samples_are_real_unique_seconds_and_consistency_needs_two() {
        let mut session = Session::new(Mode::Time, 15, false, false, false, 11).unwrap();
        let t = Instant::now();
        session.apply(Command::Tick, t);
        assert!(session.snapshot(1, t, 0).pace_wpm.is_empty());
        let first = session.prompt.chars().next().unwrap();
        session.apply(Command::Key { text: first }, t);
        session.apply(Command::Tick, t + Duration::from_secs(1));
        session.apply(Command::Tick, t + Duration::from_millis(1500));
        let one = session.snapshot(2, t + Duration::from_secs(1), 0);
        assert_eq!(one.pace_seconds, vec![1]);
        assert_eq!(one.pace_wpm.len(), 1);
        assert_eq!(one.consistency, None);
        session.apply(Command::Tick, t + Duration::from_secs(3));
        let two = session.snapshot(3, t + Duration::from_secs(3), 0);
        assert_eq!(two.pace_seconds, vec![1, 3]);
        assert!(two.consistency.is_some());
        assert_eq!(
            serde_json::to_value(&two).unwrap()["pace_seconds"],
            serde_json::json!([1, 3])
        );
    }

    #[test]
    fn correction_restores_net_speed_but_not_historical_accuracy() {
        let mut session = Session::new(Mode::Words, 10, false, false, false, 2).unwrap();
        let t = Instant::now();
        session.apply(Command::Key { text: '!' }, t);
        session.apply(Command::Backspace, t + Duration::from_millis(100));
        session.apply(
            Command::Key {
                text: session.prompt.chars().next().unwrap(),
            },
            t,
        );
        assert_eq!(session.typed.len(), 1);
        assert_eq!(session.score(t + Duration::from_secs(1)).2, 50.0);
        assert_eq!(session.score(t + Duration::from_secs(1)).3, 1);
    }

    #[test]
    fn strict_mode_ends_immediately_and_does_not_complete() {
        let mut session = Session::new(Mode::Words, 10, true, false, false, 3).unwrap();
        session.apply(Command::Key { text: '!' }, Instant::now());
        assert_eq!(session.phase, Phase::Failed);
        assert!(!session.newly_finished);
    }

    #[test]
    fn word_mode_completes_at_prompt_end() {
        let mut session = Session::new(Mode::Words, 10, false, false, false, 4).unwrap();
        let t = Instant::now();
        for (i, text) in session.prompt.clone().chars().enumerate() {
            session.apply(
                Command::Key { text },
                t + Duration::from_millis(i as u64 * 50),
            );
        }
        assert_eq!(session.phase, Phase::Finished);
        assert!(session.newly_finished);
    }

    #[test]
    fn invalid_settings_and_control_keys_do_not_start_a_run() {
        assert!(Session::new(Mode::Time, 7, false, false, false, 1).is_err());
        let mut session = Session::new(Mode::Time, 30, false, false, false, 1).unwrap();
        session.apply(Command::Key { text: '\n' }, Instant::now());
        assert_eq!(session.phase, Phase::Ready);
    }

    #[test]
    fn optional_punctuation_and_numbers_are_generated() {
        let session = Session::new(Mode::Words, 10, false, true, true, 5).unwrap();
        assert!(session.prompt.contains(','));
        assert!(session.prompt.contains('.'));
        assert!(session.prompt.bytes().any(|byte| byte.is_ascii_digit()));
        assert_eq!(session.prompt.split_whitespace().count(), 10);
    }
}
