import assert from 'node:assert/strict';
import {test} from 'node:test';
import {normalize, runTagger} from './runner.js';

test('duration normalization preserves nanosecond precision and int64 endpoints', () => {
	for (const [canonical, expected] of [
		['0s', '0'],
		['-0.000000001s', '-1'],
		['1h30m0.5s', '5400500000000'],
		['2562047h47m16.854775807s', '9223372036854775807'],
		['-2562047h47m16.854775808s', '-9223372036854775808'],
	]) {
		assert.deepEqual(normalize({type: 'duration', canonical}), {type: 'duration', value: expected});
	}
});

test('the oracle rejects incomplete and overprecise duration spellings', () => {
	for (const canonical of ['', '-', '1s junk', 'junk1s', '1s\n', '1.5m', '1s1h', '1s2s', '0.0000000001s']) {
		assert.throws(() => normalize({type: 'duration', canonical}), /duration/iv);
	}
});

test('normalization preserves object keys that shadow JavaScript prototypes', () => {
	const value = JSON.parse('{"__proto__":{"type":"duration","canonical":"1s"},"constructor":[{"type":"string","value":"hello"}]}');
	const normalized = normalize(value);
	assert.equal(Object.getPrototypeOf(normalized), Object.prototype);
	assert.deepEqual(normalized.__proto__, {type: 'duration', value: '1000000000'});
	assert.deepEqual(normalized.constructor, [{type: 'string', value: 'hello'}]);
	assert.equal(Object.hasOwn(Object.prototype, 'type'), false);
});

test('the tagger accepts an empty batch without launching AppleScript', () => {
	assert.deepEqual(runTagger([]), new Map());
});

test('the tagger rejects paths that cannot be represented in its line protocol', () => {
	for (const file of ['', 'a\nb', 'a\rb', 'a\0b', undefined, 123]) {
		assert.throws(() => runTagger([file]), /path/iv);
	}
});

test('the tagger rejects duplicate fixture paths before starting a subprocess', () => {
	assert.throws(() => runTagger(['same.soml', 'same.soml']), /duplicate/iv);
});

test('normalization preserves primitive values in arbitrary nested data', () => {
	assert.deepEqual(normalize({empty: null, flag: true, count: 42, text: 'hello', list: [null, false, 0]}), {empty: null, flag: true, count: 42, text: 'hello', list: [null, false, 0]});
});

test('canonical duration validation rejects noncanonical and overflowing values', () => {
	for (const canonical of ['00s', '01h', '1h60m', '1m60s', '1h0s', '-0s', '0.000s', '1.10s', '2562047h47m16.854775808s', '-2562047h47m16.854775809s']) {
		assert.throws(() => normalize({type: 'duration', canonical}), /duration/iv);
	}
});
