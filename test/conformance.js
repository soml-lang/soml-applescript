/*
Runs the conformance suite in `test/conformance` through the library. `tagger.applescript` decodes and encodes every case in one `osascript` process, and the tests compare its results with the suite.

	make conformance

Set `SHOW_REASONS=1` to print the cases whose error message differs from the reason of the JavaScript reference implementation, which is informative.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

const suite = path.join(import.meta.dirname, 'conformance');

function listCases(directory) {
	return fs.globSync('**/*.soml', {cwd: path.join(suite, directory)})
		.filter(file => !file.endsWith('.canonical.soml') && !file.endsWith('.formatted.soml'))
		.map(file => path.join(suite, directory, file))
		.sort();
}

const validFiles = listCases('valid');
const invalidFiles = listCases('invalid');
const results = runTagger([...validFiles, ...invalidFiles]);
const reasons = JSON.parse(fs.readFileSync(path.join(suite, 'invalid-reasons.json'), 'utf8'));

test('the suite has cases', () => {
	assert.ok(validFiles.length > 300);
	assert.ok(invalidFiles.length > 300);
});

for (const file of validFiles) {
	const name = path.relative(path.join(suite, 'valid'), file).replace(/\.soml$/v, '');

	test(`valid: ${name}`, () => {
		const result = results.get(file);
		assert.ok(result, 'No result');
		assert.ok(result.ok, `Rejected: ${result.message}`);
		assert.equal(result.writeError, undefined);
		const expected = JSON.parse(fs.readFileSync(file.replace(/\.soml$/v, '.json'), 'utf8'));
		assert.deepEqual(normalize(result.value), expected);
		assert.equal(result.canonical, fs.readFileSync(file.replace(/\.soml$/v, '.canonical.soml'), 'utf8'));
		assert.equal(result.roundTrip, result.canonical);
	});
}

const differentReasons = [];

for (const file of invalidFiles) {
	const name = path.relative(path.join(suite, 'invalid'), file).replace(/\.soml$/v, '');

	test(`invalid: ${name}`, () => {
		const result = results.get(file);
		assert.ok(result, 'No result');
		assert.equal(result.ok, false, 'Accepted');
		assert.equal(result.number, 1, result.message);
		const expected = reasons[name];
		assert.ok(expected, 'No reason in invalid-reasons.json');
		assert.deepEqual({line: result.line, column: result.column}, {line: expected.line, column: expected.column}, `${result.message}\nReference: ${expected.reason}`);

		if (!result.message.startsWith(expected.reason)) {
			differentReasons.push(`${name}\n  this:      ${result.message}\n  reference: ${expected.reason}`);
		}
	});
}

test('error reasons', () => {
	if (process.env.SHOW_REASONS) {
		console.log(differentReasons.join('\n'));
	}

	console.log(`${invalidFiles.length - differentReasons.length} of ${invalidFiles.length} error messages match the reference`);
	assert.deepEqual(differentReasons, []);
});
