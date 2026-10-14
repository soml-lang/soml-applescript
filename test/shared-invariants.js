/*
Independent boundary checks for native diagnostic fast paths. These compare short and long inputs against the same Unicode oracle and check that escaping is idempotent.
*/
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';

const root = path.join(import.meta.dirname, '..');
using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-shared-invariants-'));
const cases = [];
const unsafe = /[\u0000-\u0008\u000A-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028-\u202E\u2060-\u206F\uFEFF]/gv;
const codePoints = new Set();
for (const [start, end] of [[0, 33], [126, 161], [172, 174], [1563, 1565], [8202, 8208], [8231, 8239], [8287, 8304], [65278, 65280]]) {
	for (let codePoint = start; codePoint <= end; codePoint++) {
		codePoints.add(codePoint);
	}
}

for (const codePoint of codePoints) {
	for (const prefix of ['', 'é🦄'.repeat(260)]) {
		const source = `${prefix}${String.fromCodePoint(codePoint)}tail`;
		const expected = source.replace(unsafe, character => `\\u{${character.codePointAt(0).toString(16)}}`);
		cases.push({name: `sanitize U+${codePoint.toString(16)}, prefix ${prefix.length}`, source, expected});
	}
}

const previews = ['é🦄text', `e${'\u0301'.repeat(20_000)}tail`, `${'x'.repeat(39)}🦄end`, '\uFEFF\uFFFE🦄tail'];
for (const source of previews) {
	for (const limit of [1, 2, 3, 40]) {
		let end = limit;
		if (source.length > limit && source.charCodeAt(end - 1) >= 0xD800 && source.charCodeAt(end - 1) <= 0xDBFF) {
			end--;
		}

		cases.push({name: `preview ${previews.indexOf(source)}, limit ${limit}`, source, limit, expected: source.length <= limit ? source : `${source.slice(0, end)}…`});
	}
}

const manifestPath = path.join(temporary.path, 'cases.json');
const outputPath = path.join(temporary.path, 'results.json');
const scriptPath = path.join(temporary.path, 'check.applescript');
fs.writeFileSync(manifestPath, JSON.stringify(cases.map(testCase => ({...testCase, codes: [...testCase.source].map(character => character.codePointAt(0))}))));
fs.writeFileSync(scriptPath, String.raw`use framework "Foundation"
use soml : script "SOML"
on run {manifestPath, outputPath}
	set manifestData to current application's NSData's dataWithContentsOfFile:manifestPath
	set manifest to current application's NSJSONSerialization's JSONObjectWithData:manifestData options:0 |error|:(missing value)
	set failures to current application's NSMutableArray's array()
	repeat with step from 0 to ((manifest's |count|()) as integer) - 1
		set theCase to manifest's objectAtIndex:step
		set sourceText to string id ((theCase's objectForKey:"codes") as list)
		set previewLimit to theCase's objectForKey:"limit"
		if previewLimit is missing value then
			set actual to soml's sanitize(sourceText)
			if id of soml's sanitize(actual) is not id of actual then
				error "Sanitizing twice changed the result"
			end if
		else
			set actual to soml's abbreviate(sourceText, previewLimit as integer)
		end if
		failures's addObject:("x" & actual)
	end repeat
	set resultData to current application's NSJSONSerialization's dataWithJSONObject:failures options:0 |error|:(missing value)
	resultData's writeToFile:outputPath atomically:true
end run
`);
execFileSync('osascript', [scriptPath, manifestPath, outputPath], {
	env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
	stdio: ['ignore', 'pipe', 'pipe'],
	timeout: 30_000,
});
const results = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
assert.equal(results.length, cases.length);
for (const [index, {name, expected}] of cases.entries()) {
	test(name, () => {
		assert.equal(results[index], `x${expected}`);
	});
}
