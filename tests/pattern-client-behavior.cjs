// Exercises the QML routing functions with a fake core; no host files are touched.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');

// The two named functions are deliberately kept free of QML-only syntax so they
// can be exercised without launching a desktop session.
function load(name, next) {
  const start = source.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, `missing QML function ${name}`);
  const end = source.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(end >= 0, `missing QML function ${next} after ${name}`);
  return new Function('root', `with (root) { return (${source.slice(start, end).trim()}); }`);
}

const action = load('patternAction', 'patternResponse');
const response = load('patternResponse', 'patternBehaviorEnd');
let sent = [];
const root = {
  patternEnabled: false, patternFallback: false, patternError: '',
  mode: 'words', limit: 10, strict: false, punctuation: false, numbers: false,
  send(message) { sent.push(message); },
};
const act = action(root);
const receive = response(root);

act('decline');
assert.deepEqual(sent, [], 'declining must not enable or contact the core');
act('enable');
assert.deepEqual(sent.pop(), { type: 'set_pattern_practice', enabled: true });
assert.equal(root.patternEnabled, false, 'do not claim consent was saved before acknowledgement');
receive({ type: 'pattern_practice', enabled: true });
assert.equal(root.patternEnabled, true);
act('targeted');
assert.deepEqual(sent.pop(), {
  type: 'start', mode: 'words', limit: 10, strict: false,
  punctuation: false, numbers: false, targeted: true,
});
receive({ type: 'state', targeted: true, pattern_fallback: true });
assert.equal(root.patternFallback, true, 'fallback must be visible to the UI');
act('clear');
assert.deepEqual(sent.pop(), { type: 'clear_pattern_practice' });
receive({ type: 'error', message: 'Could not clear patterns' });
assert.match(root.patternError, /Could not clear patterns/);
assert.equal(root.patternEnabled, true, 'failed clearing must not turn collection off');
act('disable');
assert.deepEqual(sent.pop(), { type: 'set_pattern_practice', enabled: false });
receive({ type: 'pattern_practice', enabled: false });
assert.equal(root.patternEnabled, false);
sent = [];
act('targeted');
assert.deepEqual(sent, [], 'targeted practice must not start while consent is disabled');
