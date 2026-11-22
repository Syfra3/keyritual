// REQ-001 -> SCN-002: recover unknown status when collection was already enabled.
// Simulated routing only; live control wiring is verified separately.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const qml = fs.readFileSync('Keyritual.qml', 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(start >= 0 && end > start, `missing ${name} or its boundary`);
  return new Function('root', `with (root) { return (${qml.slice(start, end).trim()}); }`)(root);
}
function fixture() {
  const sent = [];
  const root = {
    patternKnown: false, patternEnabled: false, patternFallback: false,
    patternError: '', patternNotice: '', pendingPatternClear: 0,
    pendingPatternRequests: {}, patternOwnsMainError: false, errorMessage: '',
    patternConsentOpen: false, patternConsentTargeted: false,
    pendingPatternConsent: 0, pendingTargetedStatus: 0,
    mode: 'words', limit: 10, strict: false, punctuation: false, numbers: false,
    send(message) { sent.push(message); return sent.length; },
  };
  root.patternAction = method('patternAction', 'patternResponse', root);
  root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
  root.patternOpenTargeted = method('patternOpenTargeted', 'patternOpenCollectionConsent', root);
  root.patternAnswerConsent = method('patternAnswerConsent', 'patternConsentEnd', root);
  return {root, sent};
}
{
  const {root, sent} = fixture();
  root.patternOpenTargeted();
  assert.deepEqual(sent, [{type: 'get_pattern_practice'}]);
  root.patternResponse({type: 'pattern_practice', id: 1, enabled: true});
  assert.equal(root.patternConsentOpen, false);
  assert.equal(sent.length, 2, 'confirmed enabled status starts targeted practice');
  assert.equal(sent[1].type, 'start');
  assert.equal(sent[1].targeted, true);
}
{
  const {root, sent} = fixture();
  root.patternOpenTargeted();
  root.patternAnswerConsent(false);
  root.patternResponse({type: 'pattern_practice', id: 1, enabled: true});
  assert.equal(sent.length, 1, 'a cancelled flow must not start after a late response');
  assert.equal(root.patternConsentOpen, false);
}
