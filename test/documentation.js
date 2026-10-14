/*
Execute the README's file-update recipe against a real temporary file, including an encoding failure before any write.
*/
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

const root = path.join(import.meta.dirname, '..');
const readme = fs.readFileSync(path.join(root, 'readme.md'), 'utf8');
const recipe = readme.split('### Change a value and write the file\n')[1]?.split('```applescript\n')[1]?.split('\n```')[0];
assert.ok(recipe, 'The file-update recipe must exist');

for (const invalid of [false, true]) {
	test(invalid ? 'file-update recipe preserves the original on encoding failure' : 'file-update recipe writes the updated value', () => {
		using temporary = fs.mkdtempDisposableSync(path.join(os.tmpdir(), 'soml-applescript-recipe-'));
		const file = path.join(temporary.path, 'config.soml');
		const script = path.join(temporary.path, 'recipe.applescript');
		const original = 'server: {port: 80}\n';
		fs.writeFileSync(file, original);
		const body = recipe.replaceAll('"/path/to/config.soml"', 'thePath').replace('to 9090', invalid ? 'to me' : 'to 9090');
		fs.writeFileSync(script, `use AppleScript version "2.8"\nuse scripting additions\nuse soml : script "SOML"\non run {thePath}\n${body}\nend run\n`);
		const run = () => execFileSync('osascript', [script, file], {
			env: {...process.env, OSA_LIBRARY_PATH: path.join(root, 'build')},
			stdio: ['ignore', 'pipe', 'pipe'],
			timeout: 10_000,
		});
		if (invalid) {
			assert.throws(run, error => error.status === 1 && error.stderr.toString().includes('Cannot encode a script object'));
			assert.equal(fs.readFileSync(file, 'utf8'), original);
		} else {
			run();
			assert.equal(fs.readFileSync(file, 'utf8'), 'server: {\n\tport: 9090\n}\n');
		}
	});
}
