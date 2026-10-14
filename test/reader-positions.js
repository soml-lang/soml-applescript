/*
Parser positions count Unicode scalars through long grapheme sequences and line feeds followed by combining marks. Expected positions come from the deliberately placed error, independently of the reader's text splitting.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

const documents = [];

function addError(name, before, after, reason) {
	const lines = before.split('\n');
	documents.push({name, bytes: Buffer.from(before + after), line: lines.length, column: [...lines.at(-1)].length + 1, reason});
}

for (const repetitions of [127, 512, 513]) {
	for (const [graphemeIndex, grapheme] of ['e\u0301', '👩🏽‍💻', '🇳🇴', '\u0301'].entries()) {
		const content = grapheme.repeat(repetitions);
		for (const [prefixIndex, prefix] of ['', `/*\n\u0301${content}\n\u0301*/\n`].entries()) {
			const name = `${repetitions} graphemes ${graphemeIndex}, prefix ${prefixIndex}`;
			addError(`unknown escape, ${name}`, `${prefix}['${content}', "${content}`, '\\q"]', 'Unknown escape');
			addError(`missing value, ${name}`, `${prefix}{"${content}": `, '}', 'Expected a value');
			addError(`array separator, ${name}`, `${prefix}['${content}' `, '?]', 'Expected “,”');
			addError(`after block string, ${name}`, `${prefix}[\n'''\n${content}\n\u0301${content}\n''']`, '?', 'Unexpected “?”');
			addError(`block Unicode escape, ${name}`, `${prefix}[\n"""\n${content}\n\u0301${content}`, '\\u{00}\n"""]', 'A Unicode escape may not have leading zeros');
			addError(`block indentation, ${name}`, `${prefix}[\n'''\n`, `${content}\n\u0301${content}\n '''\n]`, 'This line does not start with the indentation');
		}

		const value = `${content}\n\u0301${content}`;
		documents.push({name: `valid block string, ${repetitions} graphemes ${graphemeIndex}`, bytes: Buffer.from(`[\n'''\n${value}\n'''\n]`), value: [{type: 'string', value}], canonical: `[\n\t"${content}\\n\u0301${content}"\n]\n`});
		addError(`CRLF after combining line break, ${repetitions} graphemes ${graphemeIndex}`, `/*${content}\n\u0301${content}`, '\r\n*/[]', 'A carriage return');
		addError(`raw control after combining line break, ${repetitions} graphemes ${graphemeIndex}`, `/*${content}\n\u0301${content}`, '\u007F*/[]', 'A raw control character');
	}
}

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-reader-positions-'));
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

		assert.equal(result.ok, false, 'Accepted an invalid document');
		assert.equal(result.number, 1, result.message);
		assert.equal(result.line, document.line, result.message);
		assert.equal(result.column, document.column, result.message);
		assert.ok(result.message.startsWith(document.reason), result.message);
	});
}
