import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {test} from 'node:test';

const root = path.join(import.meta.dirname, '..');

test('failed build steps preserve the previous usable library', () => {
	using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-build-test-'));
	const sourcePath = path.join(temporary.path, 'source');
	const binaryPath = path.join(temporary.path, 'bin');
	const libraryPath = path.join(temporary.path, 'build/SOML.scptd');
	const stagingRoot = path.join(temporary.path, 'staging');
	fs.mkdirSync(sourcePath);
	fs.mkdirSync(path.join(temporary.path, 'scripts'));
	fs.copyFileSync(path.join(root, 'scripts/build.sh'), path.join(temporary.path, 'scripts/build.sh'));
	fs.writeFileSync(path.join(sourcePath, 'SOML.applescript'), '');
	fs.mkdirSync(binaryPath);
	fs.mkdirSync(stagingRoot);
	fs.mkdirSync(libraryPath, {recursive: true});
	fs.writeFileSync(path.join(libraryPath, 'previous-library'), 'usable');
	fs.copyFileSync(path.join(root, 'source/Info.plist'), path.join(sourcePath, 'Info.plist'));
	fs.copyFileSync(path.join(root, 'source/SOML.sdef'), path.join(sourcePath, 'SOML.sdef'));
	fs.writeFileSync(path.join(binaryPath, 'osacompile'), `#!/bin/sh
set -eu
if [ "\${SOML_TEST_COMPILER_FAILURE:-}" = 1 ]; then
	exit 7
fi
mkdir -p "$4/Contents/Resources/Scripts"
printf 'compiled' > "$4/Contents/Resources/Scripts/main.scpt"
`, {mode: 0o755});
	fs.writeFileSync(path.join(binaryPath, 'trash'), `#!/bin/sh
set -eu
mkdir -p .trash
destination=$(mktemp -d .trash/entry.XXXXXXXX)
mv "$1" "$destination/"
`, {mode: 0o755});
	const environment = {...process.env, PATH: `${binaryPath}:${process.env.PATH}`, TMPDIR: stagingRoot};
	const build = extraEnvironment => execFileSync('sh', [path.join(root, 'scripts/build.sh')], {
		cwd: temporary.path,
		env: {...environment, ...extraEnvironment},
		stdio: ['ignore', 'pipe', 'pipe'],
		timeout: 30_000,
	});
	const assertPreserved = () => {
		assert.equal(fs.readFileSync(path.join(libraryPath, 'previous-library'), 'utf8'), 'usable');
		assert.deepEqual(fs.readdirSync(stagingRoot), []);
	};

	assert.throws(() => build({SOML_TEST_COMPILER_FAILURE: '1'}), {status: 7});
	assertPreserved();
	fs.unlinkSync(path.join(sourcePath, 'SOML.sdef'));
	assert.throws(() => build(), /SOML.sdef/v);
	assertPreserved();

	fs.copyFileSync(path.join(root, 'source/SOML.sdef'), path.join(sourcePath, 'SOML.sdef'));
	fs.writeFileSync(path.join(sourcePath, 'Info.plist'), 'invalid plist');
	assert.throws(() => build());
	assertPreserved();

	fs.copyFileSync(path.join(root, 'source/Info.plist'), path.join(sourcePath, 'Info.plist'));
	fs.writeFileSync(path.join(sourcePath, 'SOML.sdef'), '<dictionary>');
	assert.throws(() => build());
	assertPreserved();

	fs.copyFileSync(path.join(root, 'source/SOML.sdef'), path.join(sourcePath, 'SOML.sdef'));
	build();
	assert.equal(fs.existsSync(path.join(libraryPath, 'previous-library')), false);
	assert.equal(fs.readFileSync(path.join(libraryPath, 'Contents/Resources/Scripts/main.scpt'), 'utf8'), 'compiled');
	assert.equal(fs.readFileSync(path.join(libraryPath, 'Contents/Resources/SOML.sdef'), 'utf8'), fs.readFileSync(path.join(root, 'source/SOML.sdef'), 'utf8'));
	assert.deepEqual(fs.readdirSync(stagingRoot), []);

	for (const resource of ['Contents/Resources/Scripts/main.scpt', 'Contents/Resources/SOML.sdef']) {
		fs.unlinkSync(path.join(libraryPath, resource));
		execFileSync('make', ['-s', '-f', path.join(root, 'Makefile'), 'build'], {
			cwd: temporary.path,
			env: environment,
			stdio: ['ignore', 'pipe', 'pipe'],
			timeout: 30_000,
		});
		assert.ok(fs.statSync(path.join(libraryPath, resource)).isFile());
	}
});

test('a failed replacement restores the previous library', () => {
	using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-build-test-'));
	const sourcePath = path.join(temporary.path, 'source');
	const binaryPath = path.join(temporary.path, 'bin');
	const libraryPath = path.join(temporary.path, 'build/SOML.scptd');
	const stagingRoot = path.join(temporary.path, 'staging');
	fs.mkdirSync(sourcePath);
	fs.mkdirSync(path.join(temporary.path, 'scripts'));
	fs.copyFileSync(path.join(root, 'scripts/build.sh'), path.join(temporary.path, 'scripts/build.sh'));
	fs.writeFileSync(path.join(sourcePath, 'SOML.applescript'), '');
	fs.mkdirSync(binaryPath);
	fs.mkdirSync(stagingRoot);
	fs.mkdirSync(libraryPath, {recursive: true});
	fs.writeFileSync(path.join(libraryPath, 'previous-library'), 'usable');
	fs.copyFileSync(path.join(root, 'source/Info.plist'), path.join(sourcePath, 'Info.plist'));
	fs.copyFileSync(path.join(root, 'source/SOML.sdef'), path.join(sourcePath, 'SOML.sdef'));
	fs.writeFileSync(path.join(binaryPath, 'osacompile'), `#!/bin/sh
set -eu
mkdir -p "$4/Contents/Resources/Scripts"
printf 'compiled' > "$4/Contents/Resources/Scripts/main.scpt"
printf '%s' "$(dirname "$4")" > staging-path
`, {mode: 0o755});
	fs.writeFileSync(path.join(binaryPath, 'trash'), `#!/bin/sh
set -eu
mkdir -p .trash
destination=$(mktemp -d .trash/entry.XXXXXXXX)
mv "$1" "$destination/"
`, {mode: 0o755});
	// Only the move of the new bundle out of the staging folder fails, optionally leaving a partial copy at the destination.
	fs.writeFileSync(path.join(binaryPath, 'mv'), `#!/bin/sh
set -eu
if [ "\${SOML_TEST_FAIL_REPLACE:-}" = 1 ] && [ "\${1##*/}" = SOML.scptd ] && [ "$2" = build/SOML.scptd ]; then
	if [ "\${SOML_TEST_PARTIAL_COPY:-}" = 1 ]; then
		mkdir -p "$2"
		printf 'partial' > "$2/partial-library"
	fi
	exit 9
fi
exec /bin/mv "$@"
`, {mode: 0o755});
	const environment = {...process.env, PATH: `${binaryPath}:${process.env.PATH}`, TMPDIR: stagingRoot};
	const build = extraEnvironment => execFileSync('sh', [path.join(root, 'scripts/build.sh')], {
		cwd: temporary.path,
		env: {...environment, ...extraEnvironment},
		stdio: ['ignore', 'pipe', 'pipe'],
		timeout: 30_000,
	});

	for (const partialCopy of ['0', '1']) {
		assert.throws(() => build({SOML_TEST_FAIL_REPLACE: '1', SOML_TEST_PARTIAL_COPY: partialCopy}), {status: 1});
		assert.equal(path.dirname(fs.readFileSync(path.join(temporary.path, 'staging-path'), 'utf8')), 'build');
		assert.equal(fs.readFileSync(path.join(libraryPath, 'previous-library'), 'utf8'), 'usable');
		assert.deepEqual(fs.readdirSync(libraryPath), ['previous-library']);
		assert.deepEqual(fs.readdirSync(path.dirname(libraryPath)), ['SOML.scptd']);
		assert.deepEqual(fs.readdirSync(stagingRoot), []);
	}
	build();
	assert.equal(fs.existsSync(path.join(libraryPath, 'previous-library')), false);
	assert.equal(fs.readFileSync(path.join(libraryPath, 'Contents/Resources/Scripts/main.scpt'), 'utf8'), 'compiled');
	assert.deepEqual(fs.readdirSync(stagingRoot), []);
});
