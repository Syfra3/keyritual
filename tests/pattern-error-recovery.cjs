// Unit-level routing regression: a successful retry must clear only the
// matching stale pattern error, not an unrelated engine error.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const qml = fs.readFileSync(path.join(__dirname, '..', 'Keyritual.qml'), 'utf8');
const start = qml.indexOf('  function patternResponse(');
assert.ok(start >= 0, 'missing patternResponse');
const end = qml.indexOf('\n  function patternBehaviorEnd(', start);
assert.ok(end >= 0, 'missing patternBehaviorEnd');
const source = qml.slice(start, end).trim();
const root = {
  patternEnabled: true,
  patternError: 'Could not save pattern practice settings',
  errorMessage: 'Could not save pattern practice settings',
  patternNotice: '',
  pendingPatternClear: 2,
};
const receive = new Function('root', `with (root) { return (${source}); }`)(root);

receive({type: 'pattern_practice', id: 2, enabled: true});
assert.equal(root.errorMessage, '', 'successful retry clears the stale matching error');
assert.equal(root.patternError, '');
assert.match(root.patternNotice, /cleared/i);

root.patternError = 'Could not save pattern practice settings';
root.errorMessage = 'An unrelated engine failure';
root.pendingPatternClear = 3;
root.patternNotice = '';
receive({type: 'pattern_practice', id: 3, enabled: true});
assert.equal(root.errorMessage, 'An unrelated engine failure', 'unrelated errors remain visible');
