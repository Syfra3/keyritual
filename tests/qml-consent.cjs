// Source-level QML consent routing regression checks; no Quickshell or host config writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const qml = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');

function between(start, end) {
  const at = qml.indexOf(start);
  assert.ok(at >= 0, `missing ${start}`);
  const stop = qml.indexOf(end, at + start.length);
  assert.ok(stop >= 0, `missing end of ${start}`);
  return qml.slice(at, stop);
}
function method(name, next) {
  const code = between(`  function ${name}(`, `\n  ${next}`);
  return new Function('root', 'engine', 'hotkeyInstall', `with (root) { return (${code.trim()}); }`);
}
const answer = method('answerGlobalShortcut', 'function requestHistory');
const receive = method('receive', 'function answerGlobalShortcut');
const keySource = between('Keys.onPressed: function(event) {', '\n      }\n\n      Flickable');
const keyHandler = new Function('root', 'hotkeyInstall', 'Qt', 'keyCatcher', `return (${keySource.slice('Keys.onPressed: '.length).trim()});`);
const qt = Object.fromEntries(['Escape', 'N', 'Y', 'Left', 'Right', 'Up', 'Down', 'Enter', 'Return', 'Space'].map((k, i) => [`Key_${k}`, i + 1]));
Object.assign(qt, { ControlModifier: 0x100, AltModifier: 0x200, MetaModifier: 0x400 });
let writes = [];
const root = {
  globalPromptOpen: true, globalPromptYesSelected: false, pendingGlobalPrompt: 0,
  globalShortcutPrompted: false, installAfterPrompt: false, globalShortcutStatus: '',
  pendingStart: 0, lastResponse: 0, commandKey: 'm', pendingBinding: 0, promptedThisOpen: true,
  opened: true, send(message) { writes.push(message); return writes.length; }
};
const engine = { running: true };
const hotkeyInstall = { running: false };
root.answerGlobalShortcut = answer(root, engine, hotkeyInstall);
root.receive = receive(root, engine, hotkeyInstall);
root.close = () => { throw Error('dialog key leaked to close'); };
root.sendStart = () => { throw Error('dialog key leaked to engine'); };
const press = keyHandler(root, hotkeyInstall, qt, { forceActiveFocus() {} });
function key(name, modifiers = 0) {
  const e = { key: qt[`Key_${name}`], modifiers, text: name.toLowerCase(), accepted: false };
  press(e);
  assert.equal(e.accepted, true, `${name} must be swallowed by dialog`);
}
function reset() {
  writes = []; root.globalPromptOpen = true; root.globalPromptYesSelected = false;
  root.globalShortcutPrompted = false; root.pendingGlobalPrompt = 0;
  root.installAfterPrompt = false; hotkeyInstall.running = false;
}
assert.match(qml, /property bool globalPromptYesSelected: false/);
assert.match(qml, /globalPromptYesSelected = false\s+globalPromptOpen = true/);
assert.match(qml, /selected: !root\.globalPromptYesSelected/);
assert.match(qml, /selected: root\.globalPromptYesSelected/);
assert.match(qml, /onActivated: \{ if \(root\.globalShortcutPrompted\) root\.globalPromptOpen = false; else root\.answerGlobalShortcut\(false\) \}/);
assert.match(qml, /onActivated: root\.answerGlobalShortcut\(true\)/);
assert.match(qml, /width: labelText\.implicitWidth \+ 8 \* scaleFactor/);
assert.match(qml, /pointer\.containsMouse && enabledControl/);
assert.match(qml, /onClicked: button\.activated\(\)/);
assert.doesNotMatch(qml, /44 \* scaleFactor/);

key('Left'); key('Up'); key('Enter');
assert.deepEqual(writes, [{ type: 'set_shortcut_prompted', value: true }]);
assert.equal(root.installAfterPrompt, false, 'No is the default');
key('Y'); key('N'); key('Escape'); key('Enter');
assert.equal(writes.length, 1, 'saving blocks keys and duplicate writes');
root.receive(JSON.stringify({ id: 1, type: 'preferences', global_shortcut_prompted: true }));
assert.equal(root.globalPromptOpen, false);
assert.equal(hotkeyInstall.running, false, 'No never starts installer');

reset(); key('Right'); assert.equal(root.globalPromptYesSelected, true);
key('Down'); key('Left'); assert.equal(root.globalPromptYesSelected, false);
key('Up'); key('Right'); key('Return');
assert.equal(root.installAfterPrompt, true);
assert.equal(writes.length, 1);
root.receive(JSON.stringify({ id: 1, type: 'preferences', global_shortcut_prompted: true }));
assert.equal(hotkeyInstall.running, true, 'saved Yes starts once');
key('Y'); key('Enter'); key('Escape');
assert.equal(writes.length, 1, 'installing blocks all paths');
hotkeyInstall.running = false; key('Y'); key('Enter');
assert.equal(writes.length, 1, 'accepted Yes cannot run again');
assert.equal(root.globalPromptOpen, false, 'Enter closes completed consent');

reset(); key('Y'); assert.equal(root.installAfterPrompt, true);
root.receive(JSON.stringify({ id: 1, type: 'error', message: 'save failed' }));
assert.equal(hotkeyInstall.running, false, 'failed save cannot install');
key('N'); assert.equal(root.installAfterPrompt, false);
assert.equal(writes.length, 2, 'decline can be retried after failed save');

reset(); key('Escape'); assert.equal(root.installAfterPrompt, false);
reset(); key('N'); assert.equal(root.installAfterPrompt, false);
reset(); key('Y', qt.ControlModifier); assert.equal(writes.length, 0, 'modified shortcuts cannot accept');
console.log('QML compact controls and consent source interactions passed');
