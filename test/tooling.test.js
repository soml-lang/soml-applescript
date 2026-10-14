import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';
import {pathToFileURL} from 'node:url';

const root = path.join(import.meta.dirname, '..');

function createTemporary(prefix) {
	return fs.mkdtempDisposableSync(path.join(os.tmpdir(), `soml-applescript-${prefix}`));
}

function createCommand(directory, name, source) {
	fs.writeFileSync(path.join(directory, name), `#!/bin/sh\nset -eu\n${source}\n`, {mode: 0o755});
}

test('encoding fixtures retain their intentional carriage returns', () => {
	for (const [name, expected] of [
		['carriage-return-in-block-string', "a: '''\n\tx\r\n\t'''\n"],
		['carriage-return-in-comment', '# x\r\na: 1\n'],
		['crlf', 'a: 1\r\nb: 2\r\n'],
	]) {
		assert.deepEqual(fs.readFileSync(path.join(root, `test/conformance/invalid/encoding/${name}.soml`)), Buffer.from(expected), name);
	}
});

test('Git preserves conformance fixture bytes without newline normalization', () => {
	const input = Buffer.from('a: 1\r\nb: 2\r\n');
	const hash = arguments_ => execFileSync('git', ['hash-object', '--stdin', ...arguments_], {cwd: root, input, encoding: 'utf8'}).trim();
	assert.equal(hash(['--path=test/conformance/invalid/encoding/crlf.soml']), hash(['--no-filters']));
});

test('benchmark Make variables reach osascript as literal arguments', () => {
	using temporary = createTemporary('make-arguments-');
	const argumentsPath = path.join(temporary.path, 'arguments.txt');
	const markerPath = path.join(temporary.path, 'injected');
	createCommand(temporary.path, 'osascript', 'printf "%s\\n" "$@" > "$SOML_TEST_ARGUMENTS"');
	for (const variable of ['FIXTURE', 'SAMPLES']) {
		const value = `"; printf injected > '${markerPath}'; #`;
		execFileSync('make', ['-s', '-o', 'build', 'bench', `${variable}=${value}`], {
			cwd: root,
			env: {...process.env, PATH: `${temporary.path}:${process.env.PATH}`, SOML_TEST_ARGUMENTS: argumentsPath},
			stdio: ['ignore', 'pipe', 'pipe'],
			timeout: 30_000,
		});
		assert.equal(fs.existsSync(markerPath), false);
		assert.ok(fs.readFileSync(argumentsPath, 'utf8').split('\n').includes(value));
	}
});

test('Make supports a Node executable path containing spaces', () => {
	using temporary = createTemporary('make-node-');
	const argumentsPath = path.join(temporary.path, 'arguments.txt');
	createCommand(temporary.path, 'node with spaces', 'printf "%s\\n" "$@" > "$SOML_TEST_ARGUMENTS"');
	execFileSync('make', ['-s', '-o', 'build', 'conformance', `NODE=${path.join(temporary.path, 'node with spaces')}`], {
		cwd: root,
		env: {...process.env, SOML_TEST_ARGUMENTS: argumentsPath},
		stdio: ['ignore', 'pipe', 'pipe'],
		timeout: 30_000,
	});
	assert.deepEqual(fs.readFileSync(argumentsPath, 'utf8').trimEnd().split('\n'), ['--test', 'test/conformance.js']);
});

test('installation keeps the existing library when copying fails and replaces dangling links', () => {
	using temporary = createTemporary('install-');
	const librariesPath = path.join(temporary.path, 'Script Libraries');
	const installedPath = path.join(librariesPath, 'SOML.scptd');
	fs.mkdirSync(installedPath, {recursive: true});
	fs.writeFileSync(path.join(installedPath, 'previous-library'), 'usable');
	createCommand(temporary.path, 'cp', 'exit 7');
	createCommand(temporary.path, 'trash', 'mkdir -p "$SOML_TEST_TRASH"\nmv "$1" "$SOML_TEST_TRASH/$(basename "$1")"');
	const environment = {...process.env, PATH: `${temporary.path}:${process.env.PATH}`, SOML_TEST_TRASH: path.join(temporary.path, 'trash-bin')};
	const install = environment => execFileSync('sh', [path.join(root, 'scripts/build.sh'), 'install', librariesPath], {cwd: root, env: environment, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30_000});
	assert.throws(() => install(environment), {status: 7});
	assert.equal(fs.readFileSync(path.join(installedPath, 'previous-library'), 'utf8'), 'usable');
	assert.deepEqual(fs.readdirSync(librariesPath), ['SOML.scptd']);

	fs.renameSync(installedPath, path.join(temporary.path, 'previous-library'));
	fs.symlinkSync(path.join(temporary.path, 'missing'), installedPath);
	fs.unlinkSync(path.join(temporary.path, 'cp'));
	install(environment);
	assert.equal(fs.lstatSync(installedPath).isSymbolicLink(), false);
	assert.ok(fs.statSync(path.join(installedPath, 'Contents/Resources/Scripts/main.scpt')).isFile());
	assert.deepEqual(fs.readdirSync(librariesPath), ['SOML.scptd']);
});

test('build rejects a symlinked output root before modifying its target', () => {
	using temporary = createTemporary('build-links-');
	const targetPath = path.join(temporary.path, 'target');
	fs.mkdirSync(targetPath);
	fs.writeFileSync(path.join(targetPath, 'sentinel'), 'safe');
	fs.symlinkSync(targetPath, path.join(temporary.path, 'build'));
	assert.throws(() => execFileSync('sh', [path.join(root, 'scripts/build.sh')], {cwd: temporary.path, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30_000}), /Refusing symlinked build directory/v);
	assert.deepEqual(fs.readdirSync(targetPath), ['sentinel']);
});

test('tagger protocol rejects incomplete and malformed result batches', () => {
	using temporary = createTemporary('tagger-protocol-');
	createCommand(temporary.path, 'osascript', 'printf "%s" "$SOML_TEST_OUTPUT" > "$3"');
	const success = {file: 'fixture.soml', ok: true, value: {}, canonical: '', ordered: '', roundTrip: ''};
	const run = output => execFileSync(process.execPath, ['--input-type=module', '-e', `import {runTagger} from ${JSON.stringify(pathToFileURL(path.join(root, 'test/runner.js')).href)}; runTagger(['fixture.soml']);`], {
		env: {...process.env, PATH: `${temporary.path}:${process.env.PATH}`, SOML_TEST_OUTPUT: output},
		stdio: ['ignore', 'pipe', 'pipe'],
		timeout: 30_000,
	});
	run(`${JSON.stringify(success)}\n`);
	run(`${JSON.stringify({file: 'fixture.soml', ok: false, message: 'invalid input', number: 1, line: null, column: null})}\n`);
	for (const output of [
		JSON.stringify(success),
		`${JSON.stringify(success)}\n\n`,
		`${JSON.stringify({file: 'fixture.soml', ok: true})}\n`,
		`${JSON.stringify({file: 'fixture.soml', ok: false})}\n`,
		`${JSON.stringify({file: 'fixture.soml', ok: false, message: 'bad', number: 1, line: -1, column: 0})}\n`,
		`${JSON.stringify({...success, file: 'unexpected.soml'})}\n`,
		`${JSON.stringify(success)}\n${JSON.stringify(success)}\n`,
	]) {
		assert.throws(() => run(output));
	}
});
