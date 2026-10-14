/*
Diagnostic previews follow the reference's 40 UTF-16-unit bound, without splitting an astral pair. Expected positions count scalars independently. ZWJ escaping retains the library's existing diagnostic safety policy.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger} from './runner.js';

const documents = [];

function preview(text) {
	if (text.length <= 40) {
		return text;
	}

	const lastUnit = text.charCodeAt(39);
	return `${text.slice(0, lastUnit >= 0xD800 && lastUnit <= 0xDBFF ? 39 : 40)}…`;
}

function addUnknownWord(name, text) {
	const reason = `Unexpected “nope”. A string value must be quoted, as in '${preview(text)}'`;
	documents.push({name, source: `x: ${text}`, reason: reason.replaceAll('\u200D', '\\u{200d}'), line: 1, column: 4});
}

const samples = [];
for (const units of [39, 40, 41]) {
	samples.push([`ASCII ${units} units`, 'k'.repeat(units)]);
	samples.push([`combining ${units} units`, `e${'\u0301'.repeat(units - 1)}`]);
	addUnknownWord(`unknown ASCII ${units} units`, `nope ${'x'.repeat(units - 5)}`);
	addUnknownWord(`unknown combining ${units} units`, `nope${'\u0301'.repeat(units - 4)}`);
}

samples.push(['astral below limit', `${'k'.repeat(37)}🦄`]);
samples.push(['astral at limit', `${'k'.repeat(38)}🦄`]);
samples.push(['astral crosses cutoff', `${'k'.repeat(39)}🦄`]);
samples.push(['astral before cutoff', `${'k'.repeat(38)}🦄x`]);
samples.push(['one long combining cluster', `e${'\u0301'.repeat(200)}`]);
samples.push(['ZWJ clusters', '👩\u200D👩'.repeat(20)]);
samples.push(['one long ZWJ cluster', `👩${'\u200D👩'.repeat(100)}`]);

for (const [name, key] of samples) {
	const beforeDuplicate = `{'${key}': 1, `;
	const keyPreview = /^[A-Za-z0-9_\-]+$/v.test(key) ? preview(key) : JSON.stringify(preview(key));
	const reason = `Duplicate key ${keyPreview}`;
	documents.push({name: `duplicate ${name}`, source: `${beforeDuplicate}'${key}': 2}`, reason: reason.replaceAll('\u200D', '\\u{200d}'), line: 1, column: [...beforeDuplicate].length + 1});
	addUnknownWord(`unknown suggestion ${name}`, `nope ${key}`);
}

addUnknownWord('original long combining suggestion', `nope${'\u0301'.repeat(200)}`);

// The instant diagnostics are the reference's message for message. Tokens of 1000 and 1001 characters pin the diagnosed length at the reference's cutoff.
const separator = 'The date and time separator in an instant is an uppercase \u201cT\u201d, not a space';
const instantFormat = 'An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or \u00b1HH:MM';
const offsetAfterSpace = `An instant's offset follows its time directly, without a space`;
// An offset on its own after a space, as in 2026-09-19T14:00:00 Z, still gets the long local-time message: the reference's short offset diagnostic needs a source scan that osacompile's identifier table (internal table overflow, -2707) has no room for in this file.
const longFraction = '1'.repeat(980);
const atLengthInstant = `2026-09-19T14:00:00.${'1'.repeat(979)}Z`;
const overLengthInstant = `2026-09-19T14:00:00.${longFraction}Z`;

function addInstantDiagnostic(name, source, reason) {
	documents.push({name, source, reason, line: 1, column: source.startsWith('a: [') ? 5 : 4});
}

addInstantDiagnostic('instant with two spaces before the time', 'a: 2026-09-19  14:00:00', `${separator}, and an instant needs the offset it was meant in, as in 2026-09-19T14:00:00Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19 14:00:00'`);
addInstantDiagnostic('instant with a tab before the time', 'a: 2026-09-19\t14:00:00', `${separator}, and an instant needs the offset it was meant in, as in 2026-09-19T14:00:00Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19 14:00:00'`);
addInstantDiagnostic('instant with a one-digit hour', 'a: 2026-09-19 1:00', `${separator}. ${instantFormat}`);
addInstantDiagnostic('instant with a one-digit hour and seconds', 'a: 2026-09-19 1:00:00', `${separator}. ${instantFormat}`);
addInstantDiagnostic('instant followed by a timezone name', 'a: 2026-01-01T00:00:00[Europe/Oslo]', 'An instant needs an offset: Z or \u00b1HH:MM');
addInstantDiagnostic('instant followed by an array bracket', 'a: [2026-09-19T14:00:00[]', 'An instant needs an offset: Z or \u00b1HH:MM');
addInstantDiagnostic('instant followed by a comma fraction', 'a: 2026-09-19T14:00:00,5x', 'An instant needs an offset: Z or \u00b1HH:MM');
addInstantDiagnostic('instant followed by a slash range', 'a: 2026-09-19T14:00:00/2026-09-20T15:00:00', 'An instant needs an offset: Z or \u00b1HH:MM');
addInstantDiagnostic('instant followed by a digit after spaces', 'a: 2026-09-19T14:00:00 5{', 'An instant needs an offset: Z or \u00b1HH:MM');
addInstantDiagnostic('instant with a malformed offset after a space', 'a: 2026-09-19T14:00:00 +02:00:00', `An instant needs an offset: Z or \u00b1HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in`);
addInstantDiagnostic('instant at the diagnosed length keeps the fraction reason', `a: ${atLengthInstant}`, `Invalid instant ${preview(atLengthInstant)}: a fractional second has at most nine digits`);
addInstantDiagnostic('instant over the diagnosed length gets the general message', `a: ${overLengthInstant}`, `Invalid instant \u201c${preview(overLengthInstant)}\u201d. ${instantFormat}`);
addInstantDiagnostic('instant over the diagnosed length with a lowercase separator', `a: 2026-09-19t${overLengthInstant.slice(11)}`, `Invalid instant \u201c${preview(`2026-09-19t${overLengthInstant.slice(11)}`)}\u201d. ${instantFormat}`);
addInstantDiagnostic('instant over the diagnosed length with a lowercase offset', `a: ${overLengthInstant.slice(0, -1)}z`, `Invalid instant \u201c${preview(`${overLengthInstant.slice(0, -1)}z`)}\u201d. ${instantFormat}`);
addInstantDiagnostic('space-separated instant over the diagnosed length', `a: 2026-09-19 14:00:00.${'1'.repeat(981)}`, `${separator}. ${instantFormat}`);

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-diagnostic-abbreviation-'));
const files = documents.map((document, index) => {
	const file = path.join(temporary.path, `${index}.soml`);
	fs.writeFileSync(file, document.source);
	return file;
});
const results = runTagger(files);

for (const [index, document] of documents.entries()) {
	test(document.name, () => {
		const result = results.get(files[index]);
		assert.equal(result.ok, false, 'Accepted an invalid document');
		assert.equal(result.number, 1, result.message);
		assert.equal(result.line, document.line, result.message);
		assert.equal(result.column, document.column, result.message);
		assert.equal(result.message, `${document.reason} at line ${document.line}, column ${document.column}`);
	});
}
