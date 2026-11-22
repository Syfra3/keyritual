// REQ-002 -> SCN-003, SCN-004, SCN-005, SCN-006.
// Proposed QML JavaScript seam: simulated routing, not a live desktop test.
const assert = require('node:assert/strict');
const fs = require('node:fs');

const qml = fs.readFileSync('Keyritual.qml', 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, `missing ${name}`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(end > start, `missing boundary ${next}`);
  return new Function('root', `with (root) { return (${qml.slice(start, end).trim()}); }`)(root);
}

function fixture() {
  const sent = [];
  const root = {
    patternKnown: true, patternEnabled: false, patternFallback: false,
    patternError: '', patternNotice: '', pendingPatternClear: 0,
    pendingPatternRequests: {}, patternOwnsMainError: false, errorMessage: '',
    patternConsentOpen: false, patternConsentTargeted: false,
    pendingPatternConsent: 0, mode: 'words', limit: 10,
    strict: false, punctuation: false, numbers: false,
    send(message) { sent.push(message); return sent.length; },
  };
  root.patternAction = method('patternAction', 'patternResponse', root);
  root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
  root.patternOpenTargeted = method('patternOpenTargeted', 'patternOpenCollectionConsent', root);
  root.patternOpenCollectionConsent = method('patternOpenCollectionConsent', 'patternAnswerConsent', root);
  root.patternAnswerConsent = method('patternAnswerConsent', 'patternConsentEnd', root);
  return { root, sent };
}

{
  const {root, sent} = fixture();
  root.patternOpenTargeted();
  assert.equal(root.patternConsentOpen, true, 'targeted practice opens consent');
  assert.deepEqual(sent, [], 'opening consent sends no requests');
  root.patternAnswerConsent(false);
  assert.deepEqual(sent, [], 'cancel does not enable collection or start practice');
}
{
  const {root, sent} = fixture();
  root.patternOpenTargeted();
  root.patternAnswerConsent(true);
  assert.deepEqual(sent, [{type: 'set_pattern_practice', enabled: true}]);
  assert.equal(root.patternEnabled, false, 'request is not confirmation');
  root.patternResponse({type: 'pattern_practice', id: 999, enabled: true});
  assert.equal(sent.length, 1, 'unrelated response cannot start practice');
  root.patternResponse({type: 'pattern_practice', id: 1, enabled: true});
  assert.equal(sent.length, 2);
  assert.equal(sent[1].type, 'start');
  assert.equal(sent[1].targeted, true);
}
{
  const {root, sent} = fixture();
  root.patternOpenCollectionConsent();
  root.patternAnswerConsent(true);
  root.patternResponse({type: 'pattern_practice', id: 1, enabled: true});
  assert.equal(sent.length, 1, 'footer consent does not start practice');
}
{
  const {root, sent} = fixture();
  root.patternOpenTargeted();
  root.patternAnswerConsent(true);
  root.patternResponse({type: 'error', id: 1, message: 'save failed'});
  assert.equal(sent.length, 1, 'failure does not start practice');
  assert.equal(root.patternEnabled, false);
  assert.match(root.patternError, /save failed/);
}
