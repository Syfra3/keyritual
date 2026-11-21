// Source structure and QML routing checks. These do not replace a live Qt test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const qml = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');
function between(start, end) {
  const first = qml.indexOf(start);
  assert.ok(first >= 0, `missing ${start}`);
  const last = qml.indexOf(end, first + start.length);
  assert.ok(last >= 0, `missing ${end}`);
  return qml.slice(first, last);
}
function method(name, next, root) {
  const source = between(`  function ${name}(`, `\n  function ${next}(`);
  return new Function('root', `with (root) { return (${source.trim()}); }`)(root);
}

// Keep the rich-text document and the plain-text error in separate controls.
// This detects the structure needed to avoid converting a rich TextEdit to
// plain text; a real Qt rendering test is still required to confirm behavior.
const passage = between('          TextEdit {\n            id: passage', '\n          MouseArea {');
assert.match(passage, /textFormat:\s*TextEdit\.RichText/);
assert.doesNotMatch(passage, /textFormat:\s*root\.errorMessage\s*\?/);
assert.match(passage, /visible:\s*!root\.errorMessage/);
assert.match(qml, /objectName:\s*["']practiceError["']/);
assert.match(qml, /textFormat:\s*Text\.PlainText/);

// A clear request must not report success until its matching reply arrives;
// errors and unrelated replies must not manufacture a successful outcome.
let sent = [];
let nextID = 0;
const root = {
  patternEnabled: true,
  patternFallback: false,
  patternError: '',
  patternNotice: '',
  pendingPatternClear: 0,
  send(message) { sent.push(message); return ++nextID; },
};
const action = method('patternAction', 'patternResponse', root);
const receive = method('patternResponse', 'patternBehaviorEnd', root);

action('clear');
assert.deepEqual(sent.pop(), {type: 'clear_pattern_practice'});
assert.equal(root.patternNotice, '', 'clear is not complete while the save is in flight');
receive({type: 'pattern_practice', id: 999, enabled: true});
assert.equal(root.patternNotice, '', 'an unrelated response is not a clear confirmation');
receive({type: 'pattern_practice', id: 1, enabled: true});
assert.match(root.patternNotice, /clear/i, 'a matching successful save is acknowledged');
assert.equal(root.patternEnabled, true);

action('clear');
assert.equal(root.patternNotice, '', 'a new clear removes the previous confirmation');
receive({type: 'error', id: 2, message: 'Could not save pattern practice settings'});
assert.equal(root.patternNotice, '', 'a failed save must not report success');
assert.match(root.patternError, /Could not save/);
assert.equal(root.patternEnabled, true);
