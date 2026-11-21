// Dispatcher-level tests for unavailable shared state and error lifetime.
// These simulate QML routing; real Qt rendering and input remain separate checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const qml = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');
function method(name, next, root) {
  const start = qml.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, `missing ${name}`);
  const end = qml.indexOf(`\n  function ${next}(`, start + 1);
  assert.ok(end >= 0, `missing ${next}`);
  return new Function('root', 'engine', 'Qt', 'keyCatcher',
    `with (root) { return (${qml.slice(start, end).trim()}); }`)(
    root, root.engine, {callLater() {}}, {forceActiveFocus() {}});
}
function setup() {
  const root = {
    patternEnabled: true, patternKnown: true, patternFallback: false,
    patternError: '', patternNotice: '', pendingPatternClear: 0,
    pendingPatternRequests: {}, patternOwnsMainError: false,
    errorMessage: '', pendingStart: 0, lastResponse: 0,
    pendingGlobalPrompt: 0, pendingBinding: 0, state: {},
    graphAnimationEnabled: false, graphReveal: {stop() {}},
    historyOpen: false, shareOpen: false, engine: {running: true},
    mode: 'words', limit: 10, strict: false, punctuation: false, numbers: false,
    nextID: 2, send() { return ++this.nextID; },
  };
  root.patternResponse = method('patternResponse', 'patternBehaviorEnd', root);
  root.receive = method('receive', 'answerGlobalShortcut', root);
  root.sendStart = method('sendStart', 'send', root);
  return root;
}

test('an ordinary request reporting inaccessible pattern state makes consent unknown', () => {
  const root = setup();
  root.receive(JSON.stringify({id: 1, type: 'error', message: 'Could not access pattern practice settings'}));
  assert.equal(root.patternKnown, false, 'cached consent must no longer be displayed as current');
  assert.match(root.errorMessage, /Could not access/);
});

test('an unrelated error survives background state but clears on explicit restart', () => {
  const root = setup();
  root.receive(JSON.stringify({id: 1, type: 'error', message: 'Unrelated engine failure'}));
  root.receive(JSON.stringify({id: 2, type: 'state', phase: 'ready'}));
  assert.equal(root.errorMessage, 'Unrelated engine failure');
  root.sendStart();
  assert.equal(root.errorMessage, '', 'an explicit restart is a deliberate retry');
});

test('opening the overlay invalidates cached consent until a fresh status arrives', () => {
  const root = setup();
  root.open = method('open', 'close', root);
  root.open('{}');
  assert.equal(root.patternKnown, false);
});
