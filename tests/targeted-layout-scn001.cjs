// REQ-001 -> SCN-001: Find targeted practice without collection clutter.
// Source-only check; live QML layout still requires separate verification.
const assert = require('node:assert/strict');
const fs = require('node:fs');

const qml = fs.readFileSync('Keyritual.qml', 'utf8');
const start = qml.indexOf('id: practiceContent');
const end = qml.indexOf('id: promptViewport', start);
assert.ok(start >= 0 && end > start, 'practice content and prompt must exist');
const beforePrompt = qml.slice(start, end);
assert.doesNotMatch(beforePrompt, /Optional coaching:/,
  'the collection explanation must not be persistently displayed above the prompt');
