/*
Native label spelling and writer output are checked independently across escaped labels, Unicode composition, controls, and strings around the display reader's 512-character boundary. Fixtures deliberately stay within AppleScript's label compiler limit and avoid leading BOM characters in values returned by run script.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const fragments = ['"', '|', '\\', '\\"', '\\|', '|"', '"|', '"\u0301', '|\u0301', '\\\u0301', '\n', '\t', '\u0000', '\u0001', '\u001B', '\u007F', 'é', 'e\u0301', '🦄', '«x»', 'a, b', 'a:{b}', '\uFEFF', '\uFFFE'];
const values = ['', '\u0301', '"\u0301', '\\"\u0301', 'x'.repeat(511), 'x'.repeat(512) + '"\u0301', 'x'.repeat(513) + '\\', '\\'.repeat(513), 'line\nvalue\tend', '\u0000\u001B\u007F', 'v\uFEFFvalue', 'v\uFFFEvalue'];

function appleScriptLiteral(text, delimiter) {
	let result = delimiter;
	for (const character of text) {
		if (character === delimiter || character === '\\') {
			result += `\\${character}`;
		} else if (character === '\n') {
			result += '\\n';
		} else if (character === '\t') {
			result += '\\t';
		} else {
			result += character;
		}
	}
	return result + delimiter;
}

function canonicalString(text) {
	if (!/['\u0000-\u001F\u007F]/v.test(text)) {
		return `'${text}'`;
	}

	let result = '"';
	for (const character of text) {
		const scalar = character.codePointAt(0);
		if (character === '"' || character === '\\') {
			result += `\\${character}`;
		} else if (character === '\n') {
			result += '\\n';
		} else if (character === '\t') {
			result += '\\t';
		} else if (scalar < 32 || scalar === 127) {
			result += `\\u{${scalar.toString(16)}}`;
		} else {
			result += character;
		}
	}
	return result + '"';
}

const cases = [];
for (const [fragmentIndex, fragment] of fragments.entries()) {
	for (const [valueIndex, value] of values.entries()) {
		const identifier = cases.length + 1;
		const key = `Audit_${identifier}_${fragment}_end`;
		const source = `return {${appleScriptLiteral(key, '|')}:{${appleScriptLiteral(value, '"')}, {marker:${identifier}}}}`;
		const keyText = /^[A-Za-z0-9_\-]+$/v.test(key) ? key : canonicalString(key);
		cases.push({
			name: `native display label ${fragmentIndex}, value ${valueIndex}`,
			source,
			identifier,
			keyScalars: [...key].map(character => character.codePointAt(0)),
			valueScalars: [...value].map(character => character.codePointAt(0)),
			expected: `${keyText}: [\n\t${canonicalString(value)}\n\t{\n\t\tmarker: ${identifier}\n\t}\n]\n`,
		});
	}
}

const harness = String.raw`use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"

on scalarValues(theText)
	set theScalars to id of theText
	if class of theScalars is integer then
		return {theScalars}
	end if
	return theScalars
end scalarValues

on run {manifestPath, outputPath}
	set manifestData to current application's NSData's dataWithContentsOfFile:manifestPath
	set theCases to current application's NSJSONSerialization's JSONObjectWithData:manifestData options:0 |error|:(missing value)
	script Store
		property results : {}
	end script
	repeat with step from 0 to ((theCases's |count|()) as integer) - 1
		set theCase to theCases's objectAtIndex:step
		set sourceText to (theCase's objectForKey:"source") as text
		set expectedKey to (theCase's objectForKey:"keyScalars") as list
		set expectedValue to (theCase's objectForKey:"valueScalars") as list
		set expectedText to (theCase's objectForKey:"expected") as text
		set identifier to (theCase's objectForKey:"identifier") as integer
		set failure to ""
		try
			set nativeRecord to run script sourceText
			-- Verify the fixture independently before invoking the library's display reader.
			set nativeKeys to ((current application's NSDictionary's dictionaryWithDictionary:nativeRecord)'s allKeys()) as list
			if (count nativeKeys) is not 1 or scalarValues(item 1 of nativeKeys) is not expectedKey then
				error "Native fixture label changed before inspection" number 99
			end if
			set nativeValues to nativeRecord as list
			if scalarValues(item 1 of item 1 of nativeValues) is not expectedValue then
				error "Native fixture value changed before inspection" number 99
			end if
			set pairs to soml's entries(nativeRecord)
			if (count pairs) is not 1 or scalarValues(item 1 of item 1 of pairs) is not expectedKey then
				error "Entry label changed" number 99
			end if
			set actualValue to item 2 of item 1 of pairs
			if (count actualValue) is not 2 or scalarValues(item 1 of actualValue) is not expectedValue or marker of item 2 of actualValue is not identifier then
				error "Entry value or association changed" number 99
			end if
			if scalarValues(soml's encode(nativeRecord)) is not scalarValues(expectedText) then
				error "Normal output changed" number 99
			end if
			if scalarValues(soml's encodeCanonical(nativeRecord)) is not scalarValues(expectedText) then
				error "Canonical output changed" number 99
			end if
		on error message number errorNumber
			set failure to message & " (" & errorNumber & ")"
		end try
		set end of Store's results to failure
	end repeat
	set context to current application's JSContext's new()
	context's setObject:(Store's results) forKeyedSubscript:"results"
	set outputText to ((context's evaluateScript:"JSON.stringify(results)")'s toString()) as text
	(current application's NSString's stringWithString:outputText)'s writeToFile:outputPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end run
`;

const root = path.join(import.meta.dirname, '..');
using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-display-labels-'));
const manifestPath = path.join(temporary.path, 'manifest.json');
const harnessPath = path.join(temporary.path, 'harness.applescript');
const outputPath = path.join(temporary.path, 'results.json');
fs.writeFileSync(manifestPath, JSON.stringify(cases));
fs.writeFileSync(harnessPath, harness);
execFileSync('osascript', [harnessPath, manifestPath, outputPath], {
	env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
	stdio: ['ignore', 'ignore', 'pipe'],
	timeout: 120_000,
});
const results = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
assert.equal(results.length, cases.length);

for (const [index, displayCase] of cases.entries()) {
	test(displayCase.name, () => {
		assert.equal(results[index], '', results[index]);
	});
}
