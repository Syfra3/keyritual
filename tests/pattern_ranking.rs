use keyritual_core::patterns::PatternStats;

#[test]
fn counts_corrected_attempts_and_normalizes_letter_pairs() {
    let mut stats = PatternStats::default();
    stats.observe(Some('A'), 'B', 'x');
    stats.observe(Some('a'), 'b', 'b');
    assert_eq!(stats.counts("b"), Some((2, 1)));
    assert_eq!(stats.counts("ab"), Some((2, 1)));
    assert_eq!(stats.counts("AB"), Some((2, 1)));
}

#[test]
fn ignores_nonletters_and_pairs_crossing_nonletters() {
    let mut stats = PatternStats::default();
    stats.observe(Some(' '), 'a', 'x');
    stats.observe(Some('a'), ',', 'x');
    stats.observe(Some('a'), '1', '2');
    assert_eq!(stats.counts("a"), Some((1, 1)));
    assert_eq!(stats.counts(" a"), None);
    assert_eq!(stats.counts("a,"), None);
    assert_eq!(stats.counts("a1"), None);
}

#[test]
fn threshold_and_distinct_pattern_error_rates_determine_word_score() {
    let mut stats = PatternStats::default();
    for actual in ['x', 'x', 'a', 'a'] {
        stats.observe(None, 'a', actual);
    }
    assert_eq!(stats.word_score("aa"), 0.0);
    stats.observe(None, 'a', 'a');
    for actual in ['x', 'b', 'b', 'b', 'b'] {
        stats.observe(Some('a'), 'b', actual);
    }
    assert!((stats.word_score("aa") - 0.4).abs() < 1e-9);
    // `b` and `ab` each contribute 0.2, alongside `a` at 0.4.
    assert!((stats.word_score("ab") - 0.8).abs() < 1e-9);
    assert_eq!(stats.word_score("z"), 0.0);
}

#[test]
fn counters_are_bounded_and_errors_never_exceed_opportunities() {
    let mut stats = PatternStats::default();
    for _ in 0..70_000 {
        stats.observe(Some('a'), 'b', 'x');
    }
    assert_eq!(stats.counts("b"), Some((u16::MAX, u16::MAX)));
    assert_eq!(stats.counts("ab"), Some((u16::MAX, u16::MAX)));
}

#[test]
fn selection_is_seeded_targets_matches_and_avoids_immediate_repeats() {
    let mut stats = PatternStats::default();
    for _ in 0..5 {
        stats.observe(None, 'a', 'x');
    }
    let candidates = ["ant", "apple", "bird"];
    let selected = stats.select_words(&candidates, 20, 42);
    assert_eq!(selected.len(), 20);
    assert_eq!(selected, stats.select_words(&candidates, 20, 42));
    assert!(selected.iter().all(|word| word == "ant" || word == "apple"));
    assert!(selected.windows(2).all(|pair| pair[0] != pair[1]));
}

#[test]
fn selection_signals_fallback_without_eligible_matches() {
    let mut stats = PatternStats::default();
    assert!(stats.select_words(&["cat", "dog"], 10, 1).is_empty());
    for _ in 0..5 {
        stats.observe(None, 'z', 'x');
    }
    assert!(stats.select_words(&["cat", "dog"], 10, 1).is_empty());
}
