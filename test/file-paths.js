/*
Relative filenames must retain their spelling through AppleScriptObjC, including a leading U+FEFF that the text bridge treats as a byte order mark.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.join(import.meta.dirname, '..');

for (const [index, [prefixCount, suffix]] of [[1, 'config.soml'], [2, 'config.soml'], [3, 'config.soml'], [1, 'é🦄.soml'], [1, 'quote\'".soml'], [1, 'line\nfeed.soml']].entries()) {
	for (const hasUnprefixedFile of [true, false]) {
		test(`relative Unicode filename ${index}: ${hasUnprefixedFile ? 'does not read its unprefixed neighbor' : 'can be read without an unprefixed neighbor'}`, () => {
			using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-file-path-'));
			const requestedPath = '\uFEFF'.repeat(prefixCount) + suffix;
			fs.writeFileSync(path.join(temporary.path, requestedPath), '[2]\n');
			if (hasUnprefixedFile) {
				fs.writeFileSync(path.join(temporary.path, requestedPath.slice(1)), '[1]\n');
			}

			const script = path.join(temporary.path, 'probe.applescript');
			fs.writeFileSync(script, `use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
on run {prefixCount, suffix}
	set requestedPath to suffix
	repeat (prefixCount as integer) times
		set requestedPath to (character id 65279) & requestedPath
	end repeat
	return item 1 of soml's decodeFile(requestedPath)
end run
			`);
			const output = execFileSync('osascript', [script, String(prefixCount), suffix], {
				cwd: temporary.path,
				env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
				encoding: 'utf8',
				stdio: ['ignore', 'pipe', 'pipe'],
				timeout: 10_000,
			});
			assert.equal(output.trim(), '2');
		});
	}
}

// Separate directories keep filesystem normalization and case matching from conflating independently valid names.
const names = ['simple.soml', 'with space.soml', 'unix:colon.soml', 'quote\'".soml', 'comma,brace{}.soml', 'é.soml', 'e\u0301.soml', 'Σ.soml', 'σ.soml', '😀👩🏽‍💻.soml', '\uFEFF-leading.soml', 'tab\tname.soml', 'newline\nname.soml'];
const shortNameCount = names.length;
// Each of these real filenames reaches a native boundary, with the Unicode examples containing exactly 255 UTF-8 bytes.
names.push('a'.repeat(244) + '.soml', 'a'.repeat(245) + '.soml', 'a'.repeat(246) + '.soml', 'a'.repeat(247) + '.soml', 'a'.repeat(250) + '.soml', 'é'.repeat(125) + '.soml', '🦄'.repeat(62) + 'ab.soml', '\uFEFF' + 'b'.repeat(247) + '.soml', 'e\u0301'.repeat(83) + 'a.soml');
using pathTypesTemporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-file-path-types-'));
const manifest = names.map((name, index) => {
	const caseDirectory = path.join(pathTypesTemporary.path, String(index));
	fs.mkdirSync(caseDirectory);
	const file = path.join(caseDirectory, name);
	if (index < shortNameCount) {
		fs.writeFileSync(file, `[${index}]\n`);
		return {file, index};
	}

	const payload = 'é🦄';
	fs.writeFileSync(file, `[${index}, '${payload}']\n`);
	return {file, index, payload};
});
const unreadablePath = path.join(pathTypesTemporary.path, 'unreadable-é🦄.soml');
fs.writeFileSync(unreadablePath, '[123]\n');
fs.chmodSync(unreadablePath, 0);
manifest.push({file: unreadablePath, index: -1}, {file: pathTypesTemporary.path, index: -1});
const manifestPath = path.join(pathTypesTemporary.path, 'manifest.json');
const scriptPath = path.join(pathTypesTemporary.path, 'probe.applescript');
const resultsPath = path.join(pathTypesTemporary.path, 'results.json');
fs.writeFileSync(manifestPath, JSON.stringify(manifest));
fs.writeFileSync(scriptPath, String.raw`use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"
on run {manifestPath, outputPath}
	set manifestData to current application's NSData's dataWithContentsOfFile:manifestPath
	set manifest to current application's NSJSONSerialization's JSONObjectWithData:manifestData options:0 |error|:(missing value)
	set results to {}
	repeat with step from 0 to ((manifest's |count|()) as integer) - 1
		set theCase to manifest's objectAtIndex:step
		set thePath to (theCase's objectForKey:"file") as text
		set expectedIndex to (theCase's objectForKey:"index") as integer
		set fileSpecifier to POSIX file thePath
		set fileAlias to fileSpecifier as alias
		repeat with theFile in {thePath, fileSpecifier, fileAlias}
			set failure to ""
			try
				set decoded to soml's decodeFile(contents of theFile)
				if expectedIndex < 0 then
					error "Accepted an unreadable file or directory" number 99
				end if
				set expectedPayload to theCase's objectForKey:"payload"
				if expectedPayload is missing value then
					if decoded is not {expectedIndex} then
						error "Read the wrong file" number 99
					end if
				else if (count decoded) is not 2 or class of item 1 of decoded is not integer or item 1 of decoded is not expectedIndex or id of item 2 of decoded is not id of (expectedPayload as text) then
					error "Read the wrong file or changed its Unicode value" number 99
				end if
			on error message number errorNumber
				if expectedIndex >= 0 or errorNumber is not -43 or message does not start with "Could not read the file " then
					set failure to message & " (" & errorNumber & ")"
				end if
			end try
			set end of results to failure
		end repeat
	end repeat
	set context to current application's JSContext's new()
	context's setObject:results forKeyedSubscript:"results"
	set outputText to ((context's evaluateScript:"JSON.stringify(results)")'s toString()) as text
	(current application's NSString's stringWithString:outputText)'s writeToFile:outputPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end run
`);
execFileSync('osascript', [scriptPath, manifestPath, resultsPath], {
	env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
	stdio: ['ignore', 'ignore', 'pipe'],
	timeout: 30_000,
});
const pathTypeResults = JSON.parse(fs.readFileSync(resultsPath, 'utf8'));
assert.equal(pathTypeResults.length, manifest.length * 3);
for (const index of manifest.keys()) {
	const fixtureName = index < names.length ? `absolute filename ${index}` : index === names.length ? 'unreadable file' : 'directory read error';
	for (const [formIndex, form] of ['text', 'POSIX file', 'alias'].entries()) {
		test(`${fixtureName}, ${form}`, () => {
			assert.equal(pathTypeResults[index * 3 + formIndex], '', pathTypeResults[index * 3 + formIndex]);
		});
	}
}
