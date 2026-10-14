import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {test} from 'node:test';

test('release validates input, requires clean main, and pushes the version before dispatching', () => {
	fs.mkdirSync('.ai-temporary', {recursive: true});
	using temporary = fs.mkdtempDisposableSync(path.resolve('.ai-temporary/release-test-'));
	const repository = path.join(temporary.path, 'repository');
	const remote = path.join(temporary.path, 'remote.git');
	const binaries = path.join(temporary.path, 'bin');
	fs.mkdirSync(repository);
	fs.mkdirSync(binaries);
	fs.mkdirSync(path.join(repository, 'source'));
	fs.copyFileSync(new URL('../release', import.meta.url), path.join(repository, 'release'));
	fs.copyFileSync(new URL('../source/Info.plist', import.meta.url), path.join(repository, 'source/Info.plist'));
	const log = path.join(temporary.path, 'gh.log');
	fs.writeFileSync(path.join(binaries, 'gh'), `#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$SOML_RELEASE_LOG"
if [ "$1" = workflow ]; then
	test "$(git rev-parse HEAD)" = "$(git ls-remote origin refs/heads/main | cut -f1)"
fi
`, {mode: 0o755});
	const environment = {...process.env, PATH: `${binaries}:${process.env.PATH}`, SOML_RELEASE_LOG: log, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'};
	const git = (...arguments_) => execFileSync('git', arguments_, {cwd: repository, env: environment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
	git('init', '--initial-branch=main');
	git('config', 'user.name', 'Test');
	git('config', 'user.email', 'test@example.com');
	git('init', '--bare', remote);
	git('remote', 'add', 'origin', remote);
	git('add', '.');
	git('commit', '-m', 'Initial');
	const run = arguments_ => spawnSync(path.join(repository, 'release'), arguments_, {cwd: temporary.path, env: environment, encoding: 'utf8'});
	for (const arguments_ of [[], ['v1.2.3'], ['1.2'], ['01.2.3'], ['1.2.3', 'extra']]) {
		const result = run(arguments_);
		assert.equal(result.status, 1);
		assert.match(result.stderr, /Usage:/v);
	}
	fs.writeFileSync(path.join(repository, 'untracked'), '');
	assert.match(run(['1.2.3']).stderr, /clean working tree on main/v);
	git('add', 'untracked');
	git('commit', '-m', 'Add file');
	git('checkout', '-b', 'other');
	assert.match(run(['1.2.3']).stderr, /clean working tree on main/v);
	assert.equal(fs.existsSync(log), false);
	git('checkout', 'main');
	const result = run(['1.2.3']);
	assert.equal(result.status, 0, result.stderr);
	assert.equal(execFileSync('plutil', ['-extract', 'CFBundleShortVersionString', 'raw', path.join(repository, 'source/Info.plist')], {encoding: 'utf8'}).trim(), '1.2.3');
	assert.equal(git('log', '-1', '--format=%s'), '1.2.3');
	assert.equal(git('status', '--porcelain'), '');
	assert.equal(fs.readFileSync(log, 'utf8'), 'auth status\nworkflow run release.yml --ref main\n');
});
