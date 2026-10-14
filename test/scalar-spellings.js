/*
Exact binary halfways test ties-to-even without asking a parser for the expected value. Explicit quote contents and integer duration totals check alternate spellings independently of SOML output.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

const documents = [];

// An integer times a power of two has an exact terminating decimal expansion.
function binaryDecimal(significand, exponent) {
	if (exponent >= 0) {
		return `${significand << BigInt(exponent)}.0`;
	}

	const places = -exponent;
	const digits = String(significand * 5n ** BigInt(places)).padStart(places + 1, '0');
	return `${digits.slice(0, -places)}.${digits.slice(-places)}`;
}

for (const [exponent, lower, upper] of [[-1022, '2.2250738585072014e-308', '2.225073858507202e-308'], [-53, '1.1102230246251565e-16', '1.1102230246251568e-16'], [0, '1.0', '1.0000000000000002'], [52, '4503599627370496.0', '4503599627370497.0'], [70, '1.1805916207174113e21', '1.1805916207174116e21'], [1023, '8.98846567431158e307', '8.988465674311582e307']]) {
	for (const adjustment of [-1n, 0n, 1n]) {
		// The midpoint is (2^53 + 1) * 2^(exponent - 53). Move 1/1024 ULP to either side. The lower significand is even.
		const source = binaryDecimal((1n << 62n) + (1n << 9n) + adjustment, exponent - 62);
		for (const sign of ['', '-']) {
			const value = sign + (adjustment <= 0n ? lower : upper);
			documents.push({name: `binary64 halfway exponent ${exponent}, adjustment ${adjustment}, sign ${sign || 'positive'}`, source: `[${sign}${source}]`, value: [{type: 'float', value}], canonical: `[\n\t${value}\n]\n`});
		}
	}
}

// An odd lower significand sends the halfway tie upward to the even upper neighbor.
for (const adjustment of [-1n, 0n, 1n]) {
	const source = binaryDecimal((1n << 62n) + 3n * (1n << 9n) + adjustment, -62);
	for (const sign of ['', '-']) {
		const value = sign + (adjustment < 0n ? '1.0000000000000002' : '1.0000000000000004');
		documents.push({name: `odd binary64 halfway adjustment ${adjustment}, sign ${sign || 'positive'}`, source: `[${sign}${source}]`, value: [{type: 'float', value}], canonical: `[\n\t${value}\n]\n`});
	}
}

for (const adjustment of [-1n, 0n, 1n]) {
	for (const sign of ['', '-']) {
		// Half the least subnormal is 2^-1075. The tie rounds to zero, which must be refused for a nonzero literal.
		const source = `[${sign}${binaryDecimal(32n + adjustment, -1080)}]`;
		const name = `zero/subnormal halfway adjustment ${adjustment}, sign ${sign || 'positive'}`;
		if (adjustment <= 0n) {
			documents.push({name, source, invalid: true});
		} else {
			const value = `${sign}5e-324`;
			documents.push({name, source, value: [{type: 'float', value}], canonical: `[\n\t${value}\n]\n`});
		}
	}
}

for (const quote of ["'", '"']) {
	for (const delimiterLength of [3, 4, 512, 513]) {
		const delimiter = quote.repeat(delimiterLength);
		const value = `${quote.repeat(delimiterLength + 1)}body`;
		const canonicalValue = quote === "'" ? `"${value}"` : `'${value}'`;
		for (const indentation of ['', ' \t']) {
			// A longer raw quote run is content; the exact run on the last line closes the block.
			const source = `[\n${delimiter}\n${indentation}${value}\n${indentation}${delimiter}\n]`;
			documents.push({name: `raw block quotes ${quote}, length ${delimiterLength}, indentation ${indentation.length}`, source, value: [{type: 'string', value}], canonical: `[\n\t${canonicalValue}\n]\n`});
			if (quote === '"') {
				const escapedSource = `[\n${delimiter}\n${indentation}${value.replaceAll('"', '\\"')}\n${indentation}${delimiter}\n]`;
				documents.push({name: `escaped block quotes, length ${delimiterLength}, indentation ${indentation.length}`, source: escapedSource, value: [{type: 'string', value}], canonical: `[\n\t${canonicalValue}\n]\n`});
			}
		}
	}
}

for (const [source, nanoseconds, canonical] of [['1h60m60s1000ms1000us1000ns', '7261001001000', '2h1m1.001001s'], ['0h0m0s999ms999us1001ns', '1000000001', '1.000000001s'], ['9223372035s999ms854776us807ns', '9223372036853776807', '2562047h47m16.853776807s'], ['2562047h47m16s854ms775us807ns', '9223372036854775807', '2562047h47m16.854775807s'], ['0h0m0s0ms0us0ns', '0', '0s']]) {
	for (const sign of nanoseconds === '0' ? [''] : ['', '-']) {
		documents.push({name: `duration component carry ${sign}${source}`, source: `[${sign}${source}]`, value: [{type: 'duration', value: sign + nanoseconds}], canonical: `[\n\t${sign}${canonical}\n]\n`});
	}
}

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-scalar-spellings-'));
const files = documents.map((document, index) => {
	const file = path.join(temporary.path, `${index}.soml`);
	fs.writeFileSync(file, document.source);
	return file;
});
const results = runTagger(files);

for (const [index, document] of documents.entries()) {
	test(document.name, () => {
		const result = results.get(files[index]);
		if (document.invalid) {
			assert.equal(result.ok, false, 'Accepted a nonzero literal that rounds to zero');
			assert.equal(result.number, 1, result.message);
			assert.equal(result.line, 1);
			assert.equal(result.column, 2);
			assert.ok(result.message.includes('too small to be told apart from zero'), result.message);
			return;
		}

		assert.equal(result.ok, true, result.message);
		assert.equal(result.writeError, undefined);
		assert.deepEqual(normalize(result.value), document.value);
		assert.equal(result.canonical, document.canonical);
		assert.equal(result.roundTrip, document.canonical);
	});
}
