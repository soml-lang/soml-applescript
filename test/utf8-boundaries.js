/*
UTF-8 boundary bytes are supplied directly. Expected errors identify the lead byte of the malformed sequence, after counting preceding Unicode scalars independently of the decoder.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

const documents = [];
const prefixes = ["['", "['é", "['€", "['🦄", "['''\n\u0301é🦄"];

function addInvalid(name, prefix, bytes, incomplete = false) {
	const lines = prefix.split('\n');
	const reason = incomplete ? 'Incomplete UTF-8 sequence at the end of the input' : `Invalid UTF-8 byte 0x${bytes[0].toString(16).toUpperCase().padStart(2, '0')}`;
	documents.push({
		name,
		bytes: Buffer.concat([Buffer.from(prefix), Buffer.from(bytes), Buffer.from(incomplete ? '' : "']\n")]),
		line: lines.length,
		column: [...lines.at(-1)].length + 1,
		reason,
	});
}

// A malformed file is scanned in bounded windows. Valid scalars may cross every window edge before the actual error.
for (const offset of [4092, 4093, 4094, 4095, 4096, 4097, 8191, 8192]) {
	for (const scalar of ['é', '€', '🦄']) {
		const prefix = `#${'a'.repeat(offset - 1)}${scalar}\n['é🦄`;
		addInvalid(`window edge ${offset}, scalar ${scalar.codePointAt(0)}`, prefix, [0xF4, 0x90, 0x80, 0x80]);
		addInvalid(`truncated window edge ${offset}, scalar ${scalar.codePointAt(0)}`, prefix, [0xF0, 0x90, 0x80], true);
	}
}

for (const lead of [0x80, 0x8F, 0xBF, 0xC0, 0xC1, 0xF5, 0xF8, 0xFF]) {
	for (const [index, prefix] of prefixes.entries()) {
		addInvalid(`invalid lead ${lead.toString(16)}, prefix ${index}`, prefix, [lead]);
	}
}

// E0 excludes overlong scalars, ED excludes surrogates, and F0/F4 bound the astral range.
const invalidSeconds = [[0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF], [0xED, 0xA0, 0x80], [0xED, 0xBF, 0xBF], [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x8F, 0xBF, 0xBF], [0xF4, 0x90, 0x80, 0x80], [0xF4, 0xBF, 0xBF, 0xBF], [0xC2, 0x7F], [0xDF, 0xC0], [0xE1, 0x00, 0x80], [0xEF, 0xFF, 0x80], [0xF1, 0x7F, 0x80, 0x80], [0xF3, 0xC0, 0x80, 0x80]];
for (const [index, bytes] of invalidSeconds.entries()) {
	for (const [prefixIndex, prefix] of [prefixes[0], prefixes[3], prefixes[4]].entries()) {
		addInvalid(`invalid second byte ${index}, prefix ${prefixIndex}`, prefix, bytes);
	}
}

const truncatedPrefixes = [[0xC2], [0xDF], [0xE0], [0xE0, 0xA0], [0xED, 0x9F], [0xEF, 0xBF], [0xF0], [0xF0, 0x90], [0xF0, 0x90, 0x80], [0xF4, 0x8F, 0xBF]];
for (const [index, bytes] of truncatedPrefixes.entries()) {
	for (const [prefixIndex, prefix] of [prefixes[0], prefixes[2], prefixes[4]].entries()) {
		addInvalid(`truncated valid prefix ${index}, prefix ${prefixIndex}`, prefix, bytes, true);
	}
}

// A prefix already outside the scalar range is invalid, even if the file ends before its remaining bytes.
for (const [index, bytes] of [[0xE0, 0x9F], [0xED, 0xA0], [0xF0, 0x8F], [0xF4, 0x90]].entries()) {
	for (const [prefixIndex, prefix] of [prefixes[0], prefixes[3], prefixes[4]].entries()) {
		const lines = prefix.split('\n');
		documents.push({name: `invalid short prefix ${index}, prefix ${prefixIndex}`, bytes: Buffer.concat([Buffer.from(prefix), Buffer.from(bytes)]), line: lines.length, column: [...lines.at(-1)].length + 1, reason: `Invalid UTF-8 byte 0x${bytes[0].toString(16).toUpperCase()}`});
	}
}

for (const badByte of [0x00, 0x7F, 0xC0, 0xFF]) {
	for (const [position, bytes] of [[0xE1, 0x80, badByte], [0xF1, 0x80, badByte, 0x80], [0xF1, 0x80, 0x80, badByte]].entries()) {
		for (const [prefixIndex, prefix] of [prefixes[0], prefixes[1], prefixes[4]].entries()) {
			addInvalid(`noncontinuation ${badByte.toString(16)}, position ${position}, prefix ${prefixIndex}`, prefix, bytes);
		}
	}
}

// Invalid UTF-8 takes priority over an earlier BOM, raw control, or syntax error.
for (const [index, prefix] of ['\uFEFF[', '[\u0001', '\uFEFF[\u0001', 'invalid syntax\n#é🦄'].entries()) {
	addInvalid(`UTF-8 error priority ${index}`, prefix, [0xFF]);
}

documents.push({name: 'BOM precedes a raw control error', bytes: Buffer.from('\uFEFF[\u0001]'), line: 1, column: 1, reason: 'A byte order mark (BOM) is not allowed'});
documents.push({name: 'raw control precedes a syntax error', bytes: Buffer.from('invalid\n#\u0001'), line: 2, column: 2, reason: 'A raw control character'});

// U+FFFD is a valid encoded scalar, unlike a decoder replacing malformed bytes with it.
const validScalars = [[0x80, [0xC2, 0x80]], [0x7FF, [0xDF, 0xBF]], [0x800, [0xE0, 0xA0, 0x80]], [0xD7FF, [0xED, 0x9F, 0xBF]], [0xE000, [0xEE, 0x80, 0x80]], [0xFFFD, [0xEF, 0xBF, 0xBD]], [0xFFFF, [0xEF, 0xBF, 0xBF]], [0x10000, [0xF0, 0x90, 0x80, 0x80]], [0x10FFFF, [0xF4, 0x8F, 0xBF, 0xBF]]];
for (const [scalar, bytes] of validScalars) {
	const text = String.fromCodePoint(scalar);
	documents.push({name: `valid scalar U+${scalar.toString(16).toUpperCase()}`, bytes: Buffer.concat([Buffer.from("['"), Buffer.from(bytes), Buffer.from("']\n")]), value: [{type: 'string', value: text}], canonical: `[\n\t'${text}'\n]\n`});
}

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-utf8-boundaries-'));
const files = documents.map((document, index) => {
	const file = path.join(temporary.path, `${index}.soml`);
	fs.writeFileSync(file, document.bytes);
	return file;
});
const results = runTagger(files);

for (const [index, document] of documents.entries()) {
	test(document.name, () => {
		const result = results.get(files[index]);
		if (document.value !== undefined) {
			assert.equal(result.ok, true, result.message);
			assert.equal(result.writeError, undefined);
			assert.deepEqual(normalize(result.value), document.value);
			assert.equal(result.canonical, document.canonical);
			assert.equal(result.roundTrip, document.canonical);
			return;
		}

		assert.equal(result.ok, false, 'Accepted invalid bytes');
		assert.equal(result.number, 1, result.message);
		assert.equal(result.line, document.line, result.message);
		assert.equal(result.column, document.column, result.message);
		assert.ok(result.message.startsWith(document.reason), result.message);
	});
}
