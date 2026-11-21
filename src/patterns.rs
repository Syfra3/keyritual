use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Default, Serialize, Deserialize, Debug)]
pub struct PatternStats {
    counts: BTreeMap<String, (u16, u16)>,
}

impl PatternStats {
    pub fn is_empty(&self) -> bool {
        self.counts.is_empty()
    }
    pub fn observe(&mut self, previous: Option<char>, expected: char, actual: char) {
        if !expected.is_ascii_alphabetic() {
            return;
        }
        let letter = expected.to_ascii_lowercase();
        let error = expected != actual;
        self.increment(letter.to_string(), error);
        if let Some(prev) = previous.filter(char::is_ascii_alphabetic) {
            self.increment(format!("{}{}", prev.to_ascii_lowercase(), letter), error);
        }
    }

    fn increment(&mut self, key: String, error: bool) {
        let entry = self.counts.entry(key).or_default();
        entry.0 = entry.0.saturating_add(1);
        if error {
            entry.1 = entry.1.saturating_add(1).min(entry.0);
        }
    }

    pub fn counts(&self, pattern: &str) -> Option<(u16, u16)> {
        if !(1..=2).contains(&pattern.len()) || !pattern.bytes().all(|b| b.is_ascii_alphabetic()) {
            return None;
        }
        Some(
            self.counts
                .get(&pattern.to_ascii_lowercase())
                .copied()
                .unwrap_or_default(),
        )
    }

    pub fn merge(&mut self, other: &Self) {
        for (key, &(attempts, errors)) in &other.counts {
            if self.counts(key).is_none() {
                continue;
            }
            let entry = self.counts.entry(key.clone()).or_default();
            entry.0 = entry.0.saturating_add(attempts);
            entry.1 = entry.1.saturating_add(errors).min(entry.0);
        }
    }

    pub fn word_score(&self, word: &str) -> f64 {
        let bytes = word.to_ascii_lowercase().into_bytes();
        let mut patterns = std::collections::BTreeSet::new();
        for (i, &b) in bytes.iter().enumerate() {
            if !b.is_ascii_lowercase() {
                continue;
            }
            patterns.insert((b as char).to_string());
            if i > 0 && bytes[i - 1].is_ascii_lowercase() {
                patterns.insert(format!("{}{}", bytes[i - 1] as char, b as char));
            }
        }
        patterns
            .iter()
            .filter_map(|key| self.counts(key))
            .filter(|(n, e)| *n >= 5 && *e > 0)
            .map(|(n, e)| f64::from(e) / f64::from(n))
            .sum()
    }

    pub fn select_words(&self, candidates: &[&str], count: usize, seed: u64) -> Vec<String> {
        let mut choices = Vec::new();
        for &word in candidates {
            let score = self.word_score(word);
            if score > 0.0 && !choices.iter().any(|(w, _)| *w == word) {
                choices.push((word, score));
            }
        }
        if choices.is_empty() {
            return Vec::new();
        }
        let mut state = seed.max(1);
        let mut result: Vec<String> = Vec::with_capacity(count);
        for _ in 0..count {
            let available: Vec<_> = choices
                .iter()
                .filter(|(word, _)| {
                    choices.len() == 1 || result.last().is_none_or(|last| last != word)
                })
                .collect();
            let total: f64 = available.iter().map(|(_, score)| score).sum();
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            let mut value = (state as f64 / u64::MAX as f64) * total;
            let mut chosen = available[available.len() - 1].0;
            for (word, score) in available {
                if value < *score {
                    chosen = word;
                    break;
                }
                value -= score;
            }
            result.push(chosen.to_string());
        }
        result
    }
}
