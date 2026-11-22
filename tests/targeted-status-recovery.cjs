// Proposed regression: REQ-002, targeted consent after unknown status recovers.
// Simulates QML JavaScript routing; does not verify desktop UI or core I/O.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const qml = fs.readFileSync('Keyritual.qml', 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(start >= 0 && end > start, `missing ${name} or its boundary`);
  return new Function('root', `with (root) { return (${qml.slice(start, end).trim()}); }`)(root);
}
const sent = [];
const root = {
  patternKnown: false, patternEnabled: false, patternFallback: false,
  patternError: '', patternNotice: '', pendingPatternClear: 0,
  pendingPatternRequests: {}, patternOwnsMainError: false, errorMessage: '',
  patternConsentOpen: false, patternConsentTargeted: false, pendingPatternConsent: 0,
  mode: 'words', limit: 10, strict: false, punctuation: false, numbers: false,
  send(message) { sent.push(message); return sent.length; },
};
root.patternAction = method('patternAction', 'patternResponse', root);
root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
root.patternOpenTargeted = method('patternOpenTargeted', 'patternOpenCollectionConsent', root);
root.patternAnswerConsent = method('patternAnswerConsent', 'patternConsentEnd', root);
root.patternOpenTargeted();
assert.deepEqual(sent, [{type: 'get_pattern_practice'}]);
root.patternResponse({type: 'pattern_practice', id: 1, enabled: false});
root.patternAnswerConsent(true);
root.patternResponse({type: 'pattern_practice', id: 2, enabled: true});
assert.equal(sent.length, 3, 'targeted practice must start after status recovery and confirmed consent');
assert.equal(sent[2].type, 'start');
assert.equal(sent[2].targeted, true);
