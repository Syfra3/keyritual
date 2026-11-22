// Proposed regression: collection errors from a targeted start are modal.
// Simulates dispatcher messages; does not establish real desktop interaction.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const qml = fs.readFileSync('Keyritual.qml', 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(start >= 0 && end > start, `missing ${name} or its boundary`);
  return new Function('root', `with (root) { return (${qml.slice(start, end).trim()}); }`)(root);
}
const root = {
  patternKnown: true, patternEnabled: true, patternFallback: false,
  patternError: '', patternNotice: '', pendingPatternClear: 0,
  pendingPatternRequests: {}, patternOwnsMainError: false, errorMessage: '',
  patternConsentOpen: false, pendingPatternConsent: 0, pendingTargetedStatus: 0,
  pendingStart: 0, lastResponse: 0, pendingGlobalPrompt: 0, pendingBinding: 0,
  mode: 'words', limit: 10, strict: false, punctuation: false, numbers: false,
  send() { return 1; },
};
root.patternAction = method('patternAction', 'patternResponse', root);
root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
root.receive = method('receive', 'answerGlobalShortcut', root);
root.patternAction('targeted');
root.receive(JSON.stringify({id: 1, type: 'error', message: 'Enable pattern collection before targeted practice'}));
assert.equal(root.patternConsentOpen, true, 'collection error must open the modal');
assert.equal(root.patternKnown, false, 'stale collection status must not remain authoritative');
assert.match(root.patternError, /Enable pattern collection/);
assert.equal(root.errorMessage, '', 'collection error must not replace the practice prompt');
