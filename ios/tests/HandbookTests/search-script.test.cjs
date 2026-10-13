// Tests the shipped host-side script, not a retyped copy of its expression.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../../OpenCommander/CommanderHandbook.swift'), 'utf8');
const script = source.split('static let searchScript = #"""')[1].split('"""#')[0];
assert.doesNotThrow(() => new Function('needle', 'backwards', 'advance', script));
const expressionLine = script.split('\n').find(line => line.includes('const expression ='));
const expression = new Function('needle', expressionLine + 'return expression;');
for (const [query, negative] of [['a.b', 'axb'], ['[x]', 'x'], ['a\\b', 'ab'], ['.*', 'anything'], ['a+b?', 'aaab'], ['(x)$', 'x']]) {
  assert.equal(expression(query).test(query), true, query + ' matches literally');
  assert.equal(expression(query).test(negative), false, query + ' cannot become regex code');
}
for (const query of ['Rückgängig', '東京', 'Grüsse', '\u{1F4C1}', '<script>', '";throw 1;//']) {
  assert.equal(expression(query).test(query), true, 'Unicode and markup remain text');
}
assert.equal(expression('rückgängig').test('Rückgängig'), true, 'case-insensitive default');
assert(!script.includes('innerHTML') && !script.includes('eval(') && !script.includes('fetch('));
console.log('PASS shipped handbook search syntax, literal metacharacters/Unicode, case-insensitive default and text-node-only highlighting');
