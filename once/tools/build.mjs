// Build: bookmarklet.min.js (engine + entry, minified) and once-extension.zip.
//   node once/tools/build.mjs
import { readFileSync, writeFileSync, rmSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { execSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ONCE = join(dirname(fileURLToPath(import.meta.url)), '..');
const engine = readFileSync(join(ONCE, 'extension/engine.js'), 'utf8')
  .replace(/\}\)\(typeof globalThis[^\n]*\n?$/, '})(L);');
if (!engine.trim().endsWith('})(L);')) throw new Error('engine footer changed: update build.mjs');
const entry = readFileSync(join(ONCE, 'tools/bookmarklet.js'), 'utf8')
  .replace(/^\/\/.*\n/gm, '')
  .replace('ENGINE', () => engine);

const src = 'var B=(' + entry.trim() + ')';
const tmp = join(mkdtempSync(join(tmpdir(), 'once-')), 'bm.js');
writeFileSync(tmp, src);
const min = execSync(`npx -y terser@5 ${tmp} -c -m --ecma 2020`, { encoding: 'utf8' }).trim().replace(/^var B=/, '').replace(/;$/, '');
// sanity: it must still be one function expression
new Function('return ' + min)();
writeFileSync(join(ONCE, 'bookmarklet.min.js'), min + '\n');
console.log('bookmarklet.min.js', min.length, 'bytes');

rmSync(join(ONCE, 'once-extension.zip'), { force: true });
execSync('zip -qr -X ../once-extension.zip .', { cwd: join(ONCE, 'extension') });
console.log('once-extension.zip');
