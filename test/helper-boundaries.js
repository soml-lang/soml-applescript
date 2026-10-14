/*
Public scalar helpers and tagged encoding checked against independent BigInt and Gregorian calendar oracles. The corpus includes noncanonical spellings, exact conversion boundaries, fractional duration units, and signed int64 extremes.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

let randomState = 0x8A_75_14_CF;

function randomIndex(length) {
	randomState ^= randomState << 13;
	randomState ^= randomState >>> 17;
	randomState ^= randomState << 5;
	return (randomState >>> 0) % length;
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

function greatestCommonDivisor(left, right) {
	while (right !== 0n) {
		const remainder = left % right;
		left = right;
		right = remainder;
	}

	return left;
}

const durationUnits = [['h', 3_600_000_000_000n], ['m', 60_000_000_000n], ['s', 1_000_000_000n], ['ms', 1_000_000n], ['us', 1000n], ['ns', 1n]];

function canonicalDuration(value) {
	let magnitude = value < 0n ? -value : value;
	let result = value < 0n ? '-' : '';
	for (const [unit, scale] of durationUnits.slice(0, 2)) {
		const quantity = magnitude / scale;
		magnitude %= scale;
		if (quantity > 0n) {
			result += `${quantity}${unit}`;
		}
	}

	const seconds = magnitude / 1_000_000_000n;
	const fraction = String(magnitude % 1_000_000_000n).padStart(9, '0').replace(/0+$/v, '');
	if (magnitude > 0n || result === '' || result === '-') {
		result += `${seconds}${fraction === '' ? '' : `.${fraction}`}s`;
	}

	return result;
}

const cases = [];
const maximumInteger = (1n << 63n) - 1n;

function addCase(kind, source, canonical, value) {
	cases.push({kind, source, canonical, value: String(value)});
}

for (let index = 0; index < 1500; index++) {
	const [unit, scale] = durationUnits[randomIndex(durationUnits.length)];
	const fractionLength = randomIndex(14);
	const denominator = 10n ** BigInt(fractionLength);
	// Multiples of this numerator give whole nanoseconds even for fractional hours and minutes.
	const numeratorMultiple = denominator / greatestCommonDivisor(denominator, scale);
	const fraction = ((BigInt(randomIndex(1_000_000_000)) * BigInt(randomIndex(1_000_000))) % denominator) / numeratorMultiple * numeratorMultiple;
	const maximumWhole = (maximumInteger - fraction * scale / denominator) / scale;
	let whole = index % 3 === 0 ? maximumWhole - BigInt(randomIndex(10)) : BigInt(randomIndex(1_000_000));
	if (whole < 0n) {
		whole = 0n;
	}

	let value = whole * scale + fraction * scale / denominator;
	let source = groupedDigits(String(whole));
	if (fractionLength > 0) {
		source += `.${groupedDigits(String(fraction).padStart(fractionLength, '0'))}`;
	}

	source += unit;
	if (index % 2 === 0 && value !== 0n) {
		source = `-${source}`;
		value = -value;
	}

	addCase('duration', source, canonicalDuration(value), value);
}

for (const value of [maximumInteger, maximumInteger - 1n, maximumInteger - 2n, -maximumInteger - 1n, -maximumInteger, -maximumInteger + 1n]) {
	const magnitude = value < 0n ? -value : value;
	for (let lastUnit = 0; lastUnit < durationUnits.length; lastUnit++) {
		let remainder = magnitude;
		let source = value < 0n ? '-' : '';
		for (let unitIndex = 0; unitIndex < lastUnit; unitIndex++) {
			const [unit, scale] = durationUnits[unitIndex];
			const quantity = remainder / scale;
			remainder %= scale;
			if (quantity > 0n) {
				source += `${groupedDigits(String(quantity))}${unit}`;
			}
		}

		const [unit, scale] = durationUnits[lastUnit];
		if (remainder % (scale / greatestCommonDivisor(scale, 10n ** 13n)) !== 0n) {
			continue;
		}

		let fractionLength = 0;
		while ((remainder * 10n ** BigInt(fractionLength)) % scale !== 0n) {
			fractionLength++;
		}

		let numberText = String(remainder * 10n ** BigInt(fractionLength) / scale);
		if (fractionLength > 0) {
			numberText = numberText.padStart(fractionLength + 1, '0');
			numberText = `${numberText.slice(0, -fractionLength)}.${numberText.slice(-fractionLength)}`;
		}

		addCase('duration', `${source}${numberText}${unit}`, canonicalDuration(value), value);
	}
}

const integers = new Set([0n, 1n, (1n << 29n) - 1n, 1n << 29n, (1n << 29n) + 1n, (1n << 30n) - 1n, 1n << 30n, (1n << 30n) + 1n, (1n << 53n) - 1n, 1n << 53n, (1n << 53n) + 1n, maximumInteger]);
for (const [count, highLimit] of [[180, 0x8000_0000], [120, 0x20_0000]]) {
	for (let index = 0; index < count; index++) {
		integers.add((BigInt(randomIndex(highLimit)) << 32n) | BigInt(randomIndex(0x1_0000_0000)));
	}
}

for (const integer of integers) {
	for (const [radix, prefix] of [[10, ''], [16, '0x'], [8, '0o'], [2, '0b']]) {
		const leadingZeros = prefix === '' ? '' : '0'.repeat(randomIndex(6));
		const source = prefix + groupedDigits(leadingZeros + integer.toString(radix).toUpperCase());
		addCase('int', source, String(integer), integer);
	}

	if (integer !== 0n) {
		addCase('int', `-${groupedDigits(String(integer))}`, String(-integer), -integer);
	}
}

addCase('int', '-9_223_372_036_854_775_808', '-9223372036854775808', -9223372036854775808n);
for (let index = 0; index < 500; index++) {
	const local = new Date(0);
	local.setUTCFullYear(2 + randomIndex(9997), randomIndex(12), 1 + randomIndex(28));
	local.setUTCHours(randomIndex(24), randomIndex(60), randomIndex(60), 0);
	const offset = randomIndex(2879) - 1439;
	const magnitude = Math.abs(offset);
	const offsetText = `${offset < 0 ? '-' : '+'}${String(Math.floor(magnitude / 60)).padStart(2, '0')}:${String(magnitude % 60).padStart(2, '0')}`;
	const fraction = String(randomIndex(1_000_000_000)).padStart(9, '0');
	const source = `${local.toISOString().slice(0, 19)}.${fraction}${offsetText}`;
	const utc = new Date(local.getTime() - offset * 60_000);
	const trimmedFraction = fraction.replace(/0+$/v, '');
	const canonical = `${utc.toISOString().slice(0, 19)}${trimmedFraction === '' ? '' : `.${trimmedFraction}`}Z`;
	addCase('instant', source, canonical, `${utc.toISOString().slice(0, 19)}Z`);
}

const harness = String.raw`use AppleScript version "2.8"
use framework "Foundation"
use framework "JavaScriptCore"
use soml : script "SOML"

on run {manifestPath, outputPath}
	-- Only this test process uses UTC, avoiding the documented ambiguity of local dates during a DST overlap.
	current application's NSTimeZone's setDefaultTimeZone:(current application's NSTimeZone's timeZoneForSecondsFromGMT:0)
	set manifestData to current application's NSData's dataWithContentsOfFile:manifestPath
	set theCases to current application's NSJSONSerialization's JSONObjectWithData:manifestData options:0 |error|:(missing value)
	set context to current application's JSContext's new()
	script Store
		property results : {}
	end script
	repeat with step from 0 to ((theCases's |count|()) as integer) - 1
		set theCase to theCases's objectAtIndex:step
		set kindName to (theCase's objectForKey:"kind") as text
		set sourceText to (theCase's objectForKey:"source") as text
		set canonicalText to (theCase's objectForKey:"canonical") as text
		set expectedValue to (theCase's objectForKey:"value") as text
		set failure to ""
		try
			if kindName = "int" then
				set tagged to {class:SOML int, value:sourceText}
			else if kindName = "duration" then
				set tagged to {class:SOML duration, value:sourceText}
			else
				set tagged to {class:SOML instant, value:sourceText}
			end if
			set canonical to soml's encodeCanonical({tagged})
			set expectedCanonical to "[" & linefeed & tab & canonicalText & linefeed & "]" & linefeed
			if id of canonical is not id of expectedCanonical then
				error "Wrong tagged scalar canonical output: " & canonical number 99
			end if
			context's setObject:expectedValue forKeyedSubscript:"expected"
			if kindName = "int" then
				set isRepresentable to ((context's evaluateScript:"BigInt(expected) >= -9007199254740992n && BigInt(expected) <= 9007199254740992n")'s toBool()) as boolean
				if isRepresentable then
					set expectedNumber to ((context's evaluateScript:"Number(expected)")'s toDouble()) as real
					set actualNumber to soml's toNumber(tagged)
					if actualNumber is not expectedNumber or class of actualNumber is not in {integer, real} then
						error "Wrong exact integer conversion" number 99
					end if
				else
					try
						soml's toNumber(tagged)
						error "Accepted an integer outside the documented conversion range" number 99
					on error message number errorNumber
						if errorNumber is not 2 then
							error message number errorNumber
						end if
					end try
				end if
			else if kindName = "duration" then
				set expectedNumber to ((context's evaluateScript:"Number(expected) / 1e9")'s toDouble()) as real
				set actualNumber to soml's toSeconds(tagged)
				-- Conversion to seconds is documented as rounded; exact nanoseconds are checked by canonical encoding above.
				set tolerance to expectedNumber * 4.440892098500626E-16
				if tolerance < 0 then
					set tolerance to -tolerance
				end if
				set difference to actualNumber - expectedNumber
				if difference < 0 then
					set difference to -difference
				end if
				if class of actualNumber is not real or difference > tolerance then
					error "Wrong duration conversion: expected " & expectedNumber & ", got " & actualNumber number 99
				end if
			else
				set actualDate to soml's toDate(tagged)
				set expectedCanonical to "[" & linefeed & tab & expectedValue & linefeed & "]" & linefeed
				if class of actualDate is not date or id of soml's encodeCanonical({actualDate}) is not id of expectedCanonical then
					error "Wrong date conversion" number 99
				end if
			end if
		on error message number errorNumber
			set failure to message & " (" & errorNumber & ")"
		end try
		set end of Store's results to failure
	end repeat
	context's setObject:(Store's results) forKeyedSubscript:"results"
	set outputText to ((context's evaluateScript:"JSON.stringify(results)")'s toString()) as text
	(current application's NSString's stringWithString:outputText)'s writeToFile:outputPath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
end run
`;

const root = path.join(import.meta.dirname, '..');
using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-helper-boundaries-'));
const harnessPath = path.join(temporary.path, 'harness.applescript');
fs.writeFileSync(harnessPath, harness);
// One run of the harness is one process, and a process holds about 8,000 record labels before AppleScript itself fails, so the cases run in batches that stay well inside that budget whatever the size of the library.
const results = [];
const batchSize = 1000;
for (let start = 0; start < cases.length; start += batchSize) {
	const manifestPath = path.join(temporary.path, `manifest-${start}.json`);
	const outputPath = path.join(temporary.path, `results-${start}.json`);
	fs.writeFileSync(manifestPath, JSON.stringify(cases.slice(start, start + batchSize)));
	execFileSync('osascript', [harnessPath, manifestPath, outputPath], {
		env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
		stdio: ['ignore', 'ignore', 'pipe'],
		timeout: 120_000,
	});
	results.push(...JSON.parse(fs.readFileSync(outputPath, 'utf8')));
}
assert.equal(results.length, cases.length);

for (const [index, scalar] of cases.entries()) {
	test(`helper boundary ${index}: ${scalar.kind} ${scalar.source}`, () => {
		assert.equal(results[index], '', results[index]);
	});
}
