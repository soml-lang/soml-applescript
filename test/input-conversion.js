/*
Documented file inputs must resolve symlinks and dot segments without changing Unicode values. Actual AppleScript text containing a lone surrogate must report its independently specified scalar position, including after combining line breaks.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.join(import.meta.dirname, '..');
using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-input-conversion-'));
const targetDirectory = path.join(temporary.path, 'actual-é\u0301🦄');
fs.mkdirSync(targetDirectory);
fs.mkdirSync(path.join(targetDirectory, 'child'));
fs.symlinkSync(path.basename(targetDirectory), path.join(temporary.path, 'directory-link'));
const fileCases = [];
const names = [];
const payload = 'unchanged-é🦄\uFEFF\uFFFE';

for (const [index, filename] of ['\uFEFF-file.soml', '👩🏽‍💻\u0301.soml'].entries()) {
	fs.writeFileSync(path.join(targetDirectory, filename), `[${index}, '${payload}']\n`);
	const linkName = `file-link-${index}`;
	fs.symlinkSync(path.join(path.basename(targetDirectory), filename), path.join(temporary.path, linkName));
	for (const [spelling, requestedPath] of [['directory symlink', path.join(temporary.path, 'directory-link', filename)], ['file symlink', path.join(temporary.path, linkName)], ['dot segment', `${targetDirectory}/child/../${filename}`]]) {
		fileCases.push({requestedPath, index});
		for (const form of ['text', 'POSIX file', 'alias']) {
			names.push(`filename ${index}, ${spelling}, ${form}`);
		}
	}
}

const textCases = [];
// These positions count Unicode scalars explicitly, rather than using Foundation's combining-sensitive line splitting.
for (const [name, prefix, line, column] of [['Unicode prefix', '/* é🦄', 1, 6], ['combining line break', '/* first\n\u0301second', 2, 8], ['two combining line breaks', '/* first\n\u0301second\n\u0301third', 3, 7]]) {
	for (const surrogate of ['high', 'low']) {
		for (const [suffixName, suffix] of [['ASCII suffix', 'a'], ['combining line break suffix', '\n\u0301']]) {
			textCases.push({prefix, line, column, surrogate, suffix});
			names.push(`${surrogate} surrogate, ${name}, ${suffixName}`);
		}
	}
}

const harness = String.raw`use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"
on run {manifestPath, outputPath}
	set inputData to current application's NSData's dataWithContentsOfFile:manifestPath
	set manifest to current application's NSJSONSerialization's JSONObjectWithData:inputData options:0 |error|:(missing value)
	set results to {}
	set fileCases to manifest's objectForKey:"files"
	repeat with step from 0 to ((fileCases's |count|()) as integer) - 1
		set theCase to fileCases's objectAtIndex:step
		set requestedPath to (theCase's objectForKey:"requestedPath") as text
		set expectedIndex to (theCase's objectForKey:"index") as integer
		set posixFile to POSIX file requestedPath
		set fileAlias to posixFile as alias
		repeat with suppliedFile in {requestedPath, posixFile, fileAlias}
			set failure to ""
			try
				set decoded to soml's decodeFile(contents of suppliedFile)
				if (count decoded) is not 2 or class of item 1 of decoded is not integer or item 1 of decoded is not expectedIndex or id of item 2 of decoded is not id of ("unchanged-é🦄" & character id 65279 & character id 65534) then
					error "Wrong file or changed value" number 99
				end if
			on error message number errorNumber
				set failure to message & " (" & errorNumber & ")"
			end try
			set end of results to failure
		end repeat
	end repeat
	set emojiText to current application's NSString's stringWithString:(character id 128512)
	set highSurrogate to (emojiText's substringToIndex:1) as text
	set lowSurrogate to (emojiText's substringFromIndex:1) as text
	set textCases to manifest's objectForKey:"texts"
	repeat with step from 0 to ((textCases's |count|()) as integer) - 1
		set theCase to textCases's objectAtIndex:step
		set prefix to (theCase's objectForKey:"prefix") as text
		set suffix to (theCase's objectForKey:"suffix") as text
		set expectedLine to (theCase's objectForKey:"line") as integer
		set expectedColumn to (theCase's objectForKey:"column") as integer
		set surrogate to highSurrogate
		if ((theCase's objectForKey:"surrogate") as text) is "low" then
			set surrogate to lowSurrogate
		end if
		set sourceText to prefix & surrogate & suffix & "*/[]"
		set failure to ""
		try
			-- Guard the fixture: conversion must not replace or drop the malformed UTF-16 before decode sees it.
			set nativeText to current application's NSString's stringWithString:sourceText
			if (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding)) is not missing value then
				error "Fixture lost its lone surrogate before decode" number 99
			end if
			try
				soml's decode(sourceText)
				error "Accepted malformed text" number 99
			on error message number errorNumber from details
				if errorNumber is not 1 or message does not contain "lone surrogate" then
					error message number errorNumber
				end if
				if |line| of details is not expectedLine or |column| of details is not expectedColumn then
					error "Wrong surrogate position: " & message number 99
				end if
			end try
		on error message number errorNumber
			set failure to message & " (" & errorNumber & ")"
		end try
		set end of results to failure
	end repeat
	set context to current application's JSContext's new()
	context's setObject:results forKeyedSubscript:"results"
	set outputText to ((context's evaluateScript:"JSON.stringify(results)")'s toString()) as text
	(current application's NSString's stringWithString:outputText)'s writeToFile:outputPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end run
`;

const manifestPath = path.join(temporary.path, 'manifest.json');
const scriptPath = path.join(temporary.path, 'harness.applescript');
const outputPath = path.join(temporary.path, 'results.json');
fs.writeFileSync(manifestPath, JSON.stringify({files: fileCases, texts: textCases}));
fs.writeFileSync(scriptPath, harness);
execFileSync('osascript', [scriptPath, manifestPath, outputPath], {
	env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
	stdio: ['ignore', 'ignore', 'pipe'],
	timeout: 30_000,
});
const results = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
assert.equal(names.length, 30);
assert.equal(results.length, names.length);
for (const [index, name] of names.entries()) {
	test(name, () => {
		assert.equal(results[index], '', results[index]);
	});
}
