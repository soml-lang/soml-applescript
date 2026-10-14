/*
Exact boundary oracles use BigInt arithmetic and the platform Gregorian calendar independently of the AppleScript implementation. Fractional seconds stay text so the instant oracle never rounds nanoseconds through Date.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {runTagger, normalize} from './runner.js';

let randomState = 0x73_4A_21_09;

function randomInteger() {
	randomState ^= randomState << 13;
	randomState ^= randomState >>> 17;
	randomState ^= randomState << 5;
	return randomState >>> 0;
}

function randomMagnitude() {
	return ((BigInt(randomInteger()) << 32n) | BigInt(randomInteger())) & ((1n << 63n) - 1n);
}

function groupedDigits(digits) {
	let result = '';
	for (const [index, digit] of [...digits].entries()) {
		if (index > 0 && (digits.length - index) % 3 === 0) {
			result += '_';
		}

		result += digit;
	}

	return result;
}

const documents = [];

function addScalar(name, source, type, value, canonical = value) {
	documents.push({name, source: `[${source}]`, value: [{type, value}], canonical: `[\n\t${canonical}\n]\n`});
}

const maximumInteger = (1n << 63n) - 1n;
const magnitudes = new Set([0n, 1n, maximumInteger - 1n, maximumInteger]);
for (const power of [29n, 30n, 53n]) {
	for (const neighbor of [-1n, 0n, 1n]) {
		magnitudes.add((1n << power) + neighbor);
	}
}

for (const magnitude of magnitudes) {
	for (const [radix, prefix] of [[10, ''], [16, '0x'], [8, '0o'], [2, '0b']]) {
		const digits = magnitude.toString(radix).toUpperCase();
		addScalar(`int boundary ${magnitude}, radix ${radix}`, prefix + digits, 'int', String(magnitude));
		if (digits.length > 3) {
			addScalar(`int boundary ${magnitude}, grouped radix ${radix}`, prefix + groupedDigits(digits), 'int', String(magnitude));
		}
	}

	if (magnitude !== 0n) {
		addScalar(`negative int boundary ${magnitude}`, `-${groupedDigits(String(magnitude))}`, 'int', String(-magnitude));
	}
}

addScalar('minimum int64', '-9_223_372_036_854_775_808', 'int', '-9223372036854775808');

// Leading zeros are valid after a radix prefix. Total ASCII line lengths exercise both sides of the reader's 512-character conversion boundary.
for (const [radix, prefix] of [[16, '0x'], [8, '0o'], [2, '0b']]) {
	for (const magnitude of [0n, 255n, maximumInteger]) {
		const digits = magnitude.toString(radix).toUpperCase();
		for (const lineLength of [511, 512, 513]) {
			const source = prefix + '0'.repeat(lineLength - prefix.length - digits.length - 2) + digits;
			assert.equal(Buffer.byteLength(`[${source}]`), lineLength);
			addScalar(`leading-zero radix ${radix}, value ${magnitude}, line length ${lineLength}`, source, 'int', String(magnitude));
		}
	}
}

for (let index = 0; index < 10; index++) {
	const magnitude = randomMagnitude();
	for (const [radix, prefix] of [[10, ''], [16, '0x'], [8, '0o'], [2, '0b']]) {
		addScalar(`random int ${index}, radix ${radix}`, prefix + groupedDigits(magnitude.toString(radix).toUpperCase()), 'int', String(magnitude));
	}
}

function decimalQuantity(magnitude, scale) {
	const whole = magnitude / scale;
	const remainder = magnitude % scale;
	if (remainder === 0n) {
		return String(whole);
	}

	const fraction = String(remainder).padStart(String(scale).length - 1, '0').replace(/0+$/v, '');
	return `${whole}.${fraction}`;
}

function canonicalDuration(value) {
	const magnitude = value < 0n ? -value : value;
	const hours = magnitude / 3_600_000_000_000n;
	const minutes = (magnitude / 60_000_000_000n) % 60n;
	const seconds = magnitude % 60_000_000_000n;
	let result = value < 0n ? '-' : '';
	if (hours > 0n) {
		result += `${hours}h`;
	}

	if (minutes > 0n) {
		result += `${minutes}m`;
	}

	if (seconds > 0n || (hours === 0n && minutes === 0n)) {
		result += `${decimalQuantity(seconds, 1_000_000_000n)}s`;
	}

	return result;
}

function durationSource(value, spelling) {
	let magnitude = value < 0n ? -value : value;
	const sign = value < 0n ? '-' : '';
	const units = [['s', 1_000_000_000n], ['ms', 1_000_000n], ['us', 1000n], ['ns', 1n]];
	if (spelling < units.length) {
		const [unit, scale] = units[spelling];
		return `${sign}${decimalQuantity(magnitude, scale)}${unit}`;
	}

	let result = sign;
	for (const [unit, scale] of [['h', 3_600_000_000_000n], ['m', 60_000_000_000n], ...units]) {
		const quantity = magnitude / scale;
		magnitude %= scale;
		if (quantity > 0n) {
			result += `${groupedDigits(String(quantity))}${unit}`;
		}
	}

	return result === '' ? '0ns' : result;
}

const durationValues = [0n, 1n, -1n, 999n, -1001n, 59_999_999_999n, 60_000_000_001n, maximumInteger, -maximumInteger - 1n];
for (let index = 0; index < 63; index++) {
	const magnitude = randomMagnitude();
	durationValues.push(index % 2 === 0 ? magnitude : -magnitude);
}

for (const [index, value] of durationValues.entries()) {
	addScalar(`exact duration ${index}, spelling ${index % 5}`, durationSource(value, index % 5), 'duration', String(value), canonicalDuration(value));
}

for (const [source, value] of [['0.0000000001h', 360n], ['0.0000000001m', 6n], ['1.000000001h', 3_600_000_003_600n], ['1h0.00000005m', 3_600_000_003_000n]]) {
	addScalar(`fractional hour or minute ${source}`, source, 'duration', String(value), canonicalDuration(value));
}

function addInstant(name, year, month, day, hour, minute, second, offsetMinutes, fraction) {
	// setUTCFullYear avoids Date.UTC's special treatment of years 00 through 99.
	const local = new Date(0);
	local.setUTCFullYear(year, month - 1, day);
	local.setUTCHours(hour, minute, second, 0);
	const offsetMagnitude = Math.abs(offsetMinutes);
	const offset = offsetMinutes === 0 ? '+00:00' : `${offsetMinutes < 0 ? '-' : '+'}${String(Math.floor(offsetMagnitude / 60)).padStart(2, '0')}:${String(offsetMagnitude % 60).padStart(2, '0')}`;
	const source = `${local.toISOString().slice(0, 19)}${fraction === '' ? '' : `.${fraction}`}${offset}`;
	const utc = new Date(local.getTime() - offsetMinutes * 60_000);
	const canonicalFraction = fraction.replace(/0+$/v, '');
	const canonical = `${utc.toISOString().slice(0, 19)}${canonicalFraction === '' ? '' : `.${canonicalFraction}`}Z`;
	addScalar(name, source, 'instant', canonical);
}

const calendarBoundaries = [[1, 1, 1, 0, 0, 0, 0, '000000001'], [1, 1, 2, 0, 0, 0, 1439, '123456789'], [99, 12, 31, 23, 59, 59, -1, '010000000'], [100, 3, 1, 0, 0, 0, 1, ''], [400, 3, 1, 0, 0, 0, 1, '999999999'], [1600, 2, 29, 23, 59, 59, -1439, '000000000'], [1900, 3, 1, 0, 0, 0, 1, '100000001'], [2000, 2, 29, 0, 0, 0, 1439, '500'], [9999, 12, 30, 23, 59, 59, -1439, '999999999'], [9999, 12, 31, 23, 59, 59, 0, '999999999']];
for (const [index, components] of calendarBoundaries.entries()) {
	addInstant(`calendar boundary ${index}`, ...components);
}

for (let index = 0; index < 62; index++) {
	const fraction = String(randomInteger() % 1_000_000_000).padStart(9, '0');
	addInstant(`offset instant ${index}`, 2 + randomInteger() % 9997, 1 + randomInteger() % 12, 1 + randomInteger() % 28, randomInteger() % 24, randomInteger() % 60, randomInteger() % 60, (randomInteger() % 2879) - 1439, fraction);
}

for (const source of ['9223372036854775808', '-9223372036854775809', '0x8000000000000000', '0o1000000000000000000000', `0b1${'0'.repeat(63)}`, '9223372036854775808ns', '-9223372036854775809ns']) {
	documents.push({name: `outside int64 range ${source}`, source: `[${source}]`, invalid: true});
}

using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-boundaries-'));
const files = documents.map((document, index) => {
	const file = path.join(temporary.path, `${index}.soml`);
	fs.writeFileSync(file, `${document.source}\n`);
	return file;
});
const results = runTagger(files);

for (const [index, document] of documents.entries()) {
	test(document.name, () => {
		const result = results.get(files[index]);
		if (document.invalid) {
			assert.equal(result.ok, false, 'Accepted a value outside the signed int64 range');
			assert.equal(result.number, 1, result.message);
			assert.equal(result.line, 1);
			assert.equal(result.column, 2);
			return;
		}

		assert.equal(result.ok, true, result.message);
		assert.equal(result.writeError, undefined);
		assert.deepEqual(normalize(result.value), document.value);
		assert.equal(result.canonical, document.canonical);
		assert.equal(result.roundTrip, document.canonical);
	});
}
