/*
Deterministic generated documents checked against an independent value and canonical-output oracle. The corpus combines keys, string delimiters, numeric spellings, comments, and collection layouts instead of repeating shared fixtures.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

let randomState = 0x504D4C;

function randomIndex(length) {
	randomState ^= randomState << 13;
	randomState ^= randomState >>> 17;
	randomState ^= randomState << 5;
	return (randomState >>> 0) % length;
}

function choose(values) {
	return values[randomIndex(values.length)];
}

function quoted(text) {
	const escaped = [...text].map(character => {
		if (character === '"' || character === '\\') {
			return `\\${character}`;
		}

		if (character === '\n') {
			return '\\n';
		}

		if (character === '\t') {
			return '\\t';
		}

		const code = character.codePointAt(0);
		if (code < 32 || code === 127) {
			return `\\u{${code.toString(16)}}`;
		}

		return character;
	}).join('');
	return `"${escaped}"`;
}

function canonicalString(text) {
	if (!/['\u0000-\u001F\u007F]/v.test(text)) {
		return `'${text}'`;
	}

	return quoted(text);
}

function canonicalKey(text) {
	return /^[\w\-]+$/v.test(text) ? text : canonicalString(text);
}

function scalarOrder(left, right) {
	const leftCodes = [...left].map(character => character.codePointAt(0));
	const rightCodes = [...right].map(character => character.codePointAt(0));
	for (let index = 0; index < Math.min(leftCodes.length, rightCodes.length); index++) {
		if (leftCodes[index] !== rightCodes[index]) {
			return leftCodes[index] - rightCodes[index];
		}
	}

	return leftCodes.length - rightCodes.length;
}

const strings = ['', 'plain', "it's", '"quoted"', '\\', 'ends\\', '\\u0000', '\\u001b', '\\u{7f}', 'line\nbreak', 'tab\tvalue', '\u001B[31m', '\u007F', '\uFEFFstart', '\uFFFEswap', 'e\u0301', 'é', '🦄', '/* not a comment */', '# not a comment', 'on run\nreturn 1\nend run'];
const keys = ['a', 'A', '0', '-key', '_', '', 'with space', 'Content-Type', 'name', 'class', '__proto__', 'constructor', 'value', 'entries', 'a.b', 'a:b', 'quote"', 'bar|', 'back\\slash', 'line\nfeed', '\uFEFFkey', '\uFFFEkey', 'é', 'e\u0301', '\uE000', '\u{10000}'];

function scalar() {
	const kind = randomIndex(8);
	if (kind === 0) {
		const value = choose(strings);
		return {source: quoted(value), canonical: canonicalString(value), value: {type: 'string', value}};
	}

	if (kind === 1) {
		const value = randomIndex(100_000);
		const source = choose([String(value), `0x${value.toString(16).toUpperCase()}`, `0o${value.toString(8)}`, `0b${value.toString(2)}`]);
		return {source, canonical: String(value), value: {type: 'int', value: String(value)}};
	}

	if (kind === 2) {
		const value = choose(['9223372036854775807', '-9223372036854775808', '9007199254740993', '-9007199254740993']);
		return {source: value, canonical: value, value: {type: 'int', value}};
	}

	if (kind === 3) {
		const [source, canonical] = choose([['-0.0', '0.0'], ['1.2500', '1.25'], ['1e3', '1000.0'], ['1e-7', '1e-7'], ['infinity', 'infinity'], ['-infinity', '-infinity'], ['0.0000000000001', '1e-13']]);
		return {source, canonical, value: {type: 'float', value: canonical}};
	}

	if (kind === 4) {
		const value = choose(['true', 'false']);
		return {source: value, canonical: value, value: {type: 'bool', value}};
	}

	if (kind === 5) {
		return {source: 'null', canonical: 'null', value: {type: 'null', value: 'null'}};
	}

	if (kind === 6) {
		const [source, canonical, value] = choose([['90s', '1m30s', '90000000000'], ['1_000ms', '1s', '1000000000'], ['-1ns', '-0.000000001s', '-1'], ['0.5h', '30m', '1800000000000'], ['1m1us', '1m0.000001s', '60000001000']]);
		return {source, canonical, value: {type: 'duration', value}};
	}

	const [source, canonical] = choose([['2026-10-14T14:00:00+02:00', '2026-10-14T12:00:00Z'], ['2024-02-29T23:59:59.123000000Z', '2024-02-29T23:59:59.123Z'], ['0001-01-01T00:00:00Z', '0001-01-01T00:00:00Z']]);
	return {source, canonical, value: {type: 'instant', value: canonical}};
}

function collection(depth, kind = choose(['array', 'object'])) {
	const count = randomIndex(6);
	if (kind === 'array') {
		const children = Array.from({length: count}, () => node(depth + 1));
		return {kind, children, source: `[${children.map(child => child.source).join(choose([', ', ', /* comment */ ', '\n', '\n# comment\n']))}]`, value: children.map(child => child.value)};
	}

	const selected = [];
	while (selected.length < count) {
		const key = choose(keys);
		if (!selected.includes(key)) {
			selected.push(key);
		}
	}

	const children = selected.map(key => ({key, node: node(depth + 1)}));
	const separator = choose([', ', ', /* comment */ ', '\n', '\n# comment\n']);
	return {kind, children, source: `{${children.map(({key, node: child}) => `${quoted(key)}:${choose([' ', '\t', '\n'])}${child.source}`).join(separator)}}`, value: Object.fromEntries(children.map(({key, node: child}) => [key, child.value]))};
}

function node(depth) {
	return depth >= 4 || randomIndex(3) > 0 ? scalar() : collection(depth);
}

function canonical(node, level = 0, root = true) {
	if (!node.kind) {
		return node.canonical;
	}

	const isObject = node.kind === 'object';
	if (node.children.length === 0) {
		return isObject ? '{}' : '[]';
	}

	const children = isObject ? node.children.toSorted((left, right) => scalarOrder(left.key, right.key)) : node.children;
	const contentLevel = root && isObject ? level : level + 1;
	const content = children.map(child => `${'\t'.repeat(contentLevel)}${isObject ? `${canonicalKey(child.key)}: ` : ''}${canonical(isObject ? child.node : child, contentLevel, false)}`).join('\n');
	if (root && isObject) {
		return content;
	}

	return `${isObject ? '{' : '['}\n${content}\n${'\t'.repeat(level)}${isObject ? '}' : ']'}`;
}

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-generated-'));
const documents = Array.from({length: 200}, () => collection(0));
const files = documents.map((document, index) => {
	const file = path.join(temporary.path, `${index}.soml`);
	fs.writeFileSync(file, `# deterministic case ${index}\n${document.source}\n`);
	return file;
});
const results = runTagger(files);

for (const [index, document] of documents.entries()) {
	test(`generated document ${index}: exact value, canonical output, and ordered round trip`, () => {
		const result = results.get(files[index]);
		assert.equal(result.ok, true, result.message);
		assert.equal(result.writeError, undefined);
		assert.deepEqual(normalize(result.value), document.value);
		assert.equal(result.canonical, `${canonical(document)}\n`);
		assert.equal(result.roundTrip, result.canonical);
	});
}
