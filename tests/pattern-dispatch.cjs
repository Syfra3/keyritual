// Dispatcher-level ordering and error ownership; no real desktop interaction.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const qml = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, `missing ${name}`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(end >= 0, `missing ${next}`);
  return new Function('root', `with (root) { return (${qml.slice(start, end).trim()}); }`)(root);
}
function setup() {
  const root = {
    patternEnabled: true, patternFallback: false, patternError: '', patternNotice: '',
    pendingPatternClear: 0, errorMessage: '', pendingStart: 0, lastResponse: 0,
    pendingGlobalPrompt: 0, pendingBinding: 0, state: {}, graphAnimationEnabled: false,
    nextID: 1, send() { return ++this.nextID; },
  };
  root.patternAction = method('patternAction', 'patternResponse', root);
  root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
  root.receive = method('receive', 'answerGlobalShortcut', root);
  return root;
}

{
  const root = setup();
  root.receive(JSON.stringify({id: 1, type: 'error', message: 'Unrelated engine failure'}));
  assert.equal(root.errorMessage, 'Unrelated engine failure');
  assert.equal(root.patternError, '', 'unrelated requests must not become pattern errors');
  root.patternAction('enable');
  root.receive(JSON.stringify({id: 2, type: 'pattern_practice', enabled: true}));
  assert.equal(root.errorMessage, 'Unrelated engine failure', 'pattern success must not erase an unrelated failure');
}

for (const reply of [
  {id: 2, type: 'error', message: 'Clear failed'},
  {id: 2, type: 'pattern_practice', enabled: true},
]) {
  const root = setup();
  root.patternAction('clear');
  root.pendingStart = 3;
  root.lastResponse = 3;
  root.receive(JSON.stringify(reply));
  assert.equal(root.pendingPatternClear, 0, 'a later start must not hide the clear outcome');
  assert.equal(root.lastResponse, 3, 'old action replies must not roll back session ordering');
  if (reply.type === 'error') {
    assert.match(root.patternError, /Clear failed/);
    assert.equal(root.patternNotice, '');
  } else {
    assert.match(root.patternNotice, /cleared/i);
  }
}
