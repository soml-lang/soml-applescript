import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';

const root = path.join(import.meta.dirname, '..');
const environment = {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')};

function runAppleScript(source) {
	return execFileSync('osascript', ['-e', source], {env: environment, encoding: 'utf8', timeout: 30_000, stdio: ['ignore', 'pipe', 'pipe']}).trim();
}

test('benchmark helpers calculate medians and report unusable fixture data', async context => {
	using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-benchmark-'));
	const scriptPath = path.join(temporary.path, 'benchmark.scpt');
	execFileSync('osacompile', ['-o', scriptPath, path.join(root, 'bench/benchmark.applescript')], {env: environment, timeout: 30_000, stdio: ['ignore', 'pipe', 'pipe']});
	const load = `set benchmark to load script POSIX file ${JSON.stringify(scriptPath)}\n`;

	await context.test('odd and even medians preserve samples and arithmetic', () => {
		assert.equal(runAppleScript(`${load}return {median({9, 1, 2}) of benchmark, median({4, 1, 3, 2}) of benchmark, median({0.125}) of benchmark}`), '2, 2.5, 0.125');
	});

	await context.test('empty medians fail with an actionable diagnostic', () => {
		assert.throws(() => runAppleScript(`${load}median({}) of benchmark`), /median of no samples/v);
	});

	await context.test('missing fixtures fail at the read boundary', () => {
		assert.throws(() => runAppleScript(`${load}readText(${JSON.stringify(path.join(temporary.path, 'missing.soml'))}) of benchmark`), /Could not read benchmark fixture/v);
	});

	await context.test('invalid UTF-8 is rejected before benchmarking', () => {
		const fixturePath = path.join(temporary.path, 'invalid.soml');
		fs.writeFileSync(fixturePath, Buffer.from([0xFF]));
		assert.throws(() => runAppleScript(`${load}readText(${JSON.stringify(fixturePath)}) of benchmark`), /not UTF-8/v);
	});

	await context.test('malformed JSON is rejected with a decoder diagnostic', () => {
		const fixturePath = path.join(temporary.path, 'invalid.json');
		fs.writeFileSync(fixturePath, '{');
		assert.throws(() => runAppleScript(`${load}set invalidData to readData(${JSON.stringify(fixturePath)}) of benchmark\ndecodeJSON(invalidData) of benchmark`), /Could not decode benchmark JSON/v);
	});
});

test('benchmark CLI rejects unknown fixtures and invalid sample counts', () => {
	const benchmarkPath = path.join(root, 'bench/benchmark.applescript');
	for (const arguments_ of [['../source/SOML', '1'], ['service', '0'], ['service', '-1'], ['service', '1.5'], ['service', '1', 'extra']]) {
		assert.throws(() => execFileSync('osascript', [benchmarkPath, ...arguments_], {env: environment, timeout: 30_000, stdio: ['ignore', 'pipe', 'pipe']}), /Usage:/v);
	}
});
