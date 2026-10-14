import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.join(import.meta.dirname, '..');
const canonicalDurationPattern = /^(?<negative>-)?(?:(?<hours>[1-9]\d{0,6})h)?(?:(?<minutes>[1-9]|[1-5]\d)m)?(?:(?<seconds>\d|[1-5]\d)(?:\.(?<fraction>\d{0,8}[1-9]))?s)?$/v;

export function runTagger(files) {
	const expectedFiles = new Set(files);
	assert.equal(expectedFiles.size, files.length, 'Duplicate fixture paths');
	for (const file of files) {
		assert.ok(typeof file === 'string' && file !== '' && !/[\r\n\0]/v.test(file), 'Fixture paths must be nonempty strings without line breaks or NUL');
	}

	if (files.length === 0) {
		return new Map();
	}
	using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-conformance-'));
	const listPath = path.join(temporary.path, 'list.txt');
	const outputPath = path.join(temporary.path, 'output.jsonl');
	fs.writeFileSync(listPath, files.join('\n'));
	execFileSync('osascript', [path.join(import.meta.dirname, 'tagger.applescript'), listPath, outputPath], {
		env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
		stdio: ['ignore', 'ignore', 'pipe'],
		maxBuffer: 1_000_000,
		timeout: 120_000,
		killSignal: 'SIGKILL',
	});

	const results = new Map();
	const output = fs.readFileSync(outputPath, 'utf8');
	assert.ok(output.endsWith('\n'), 'Incomplete tagger output');
	for (const [, line] of output.matchAll(/([^\n]*)\n/gv)) {
		const result = JSON.parse(line);
		assert.ok(result !== null && typeof result === 'object' && !Array.isArray(result) && typeof result.ok === 'boolean', 'Malformed tagger result');
		assert.ok(expectedFiles.has(result.file), 'Unexpected fixture in tagger output');
		assert.ok(!results.has(result.file), 'Duplicate fixture result');
		if (result.ok) {
			assert.ok(typeof result.writeError === 'string' || (Object.hasOwn(result, 'value') && typeof result.canonical === 'string' && typeof result.ordered === 'string' && typeof result.roundTrip === 'string'), 'Incomplete successful tagger result');
		} else {
			assert.ok(typeof result.message === 'string' && Number.isInteger(result.number), 'Malformed tagger error');
			for (const position of [result.line, result.column]) {
				assert.ok(position === null || (Number.isInteger(position) && position > 0), 'Malformed tagger error position');
			}
		}
		results.set(result.file, result);
	}

	assert.equal(results.size, files.length, 'Each fixture must produce exactly one result');
	return results;
}

// A canonical duration, such as `-1h30m0.5s`, as nanoseconds.
function durationNanoseconds(text) {
	assert.equal(typeof text, 'string', 'Invalid canonical duration');
	const match = canonicalDurationPattern.exec(text);
	assert.ok(match && match[0] === text, 'Invalid canonical duration');
	const {negative, hours, minutes, seconds, fraction} = match.groups;
	assert.ok(hours !== undefined || minutes !== undefined || seconds !== undefined, 'Empty canonical duration');
	assert.ok(seconds !== '0' || fraction !== undefined || (hours === undefined && minutes === undefined), 'Redundant zero in canonical duration');
	const total = (BigInt(hours ?? 0) * 3_600_000_000_000n) + (BigInt(minutes ?? 0) * 60_000_000_000n) + (BigInt(seconds ?? 0) * 1_000_000_000n) + BigInt((fraction ?? '').padEnd(9, '0'));
	assert.ok(!negative || total !== 0n, 'Negative zero canonical duration');
	assert.ok(total <= (negative ? 9_223_372_036_854_775_808n : 9_223_372_036_854_775_807n), 'Out-of-range canonical duration');
	return String(negative ? -total : total);
}

export function normalize(value) {
	if (value === null || typeof value !== 'object') {
		return value;
	}

	if (Array.isArray(value)) {
		return value.map(normalize);
	}

	if (value.type === 'duration' && value.canonical !== undefined) {
		return {type: 'duration', value: durationNanoseconds(value.canonical)};
	}

	if (typeof value.type === 'string' && typeof value.value === 'string' && Object.keys(value).length === 2) {
		return value;
	}

	return Object.fromEntries(Object.entries(value).values().map(([key, item]) => [key, normalize(item)]));
}
