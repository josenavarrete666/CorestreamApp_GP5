import assert from 'node:assert/strict';
import {readFile, readdir, stat} from 'node:fs/promises';
import path from 'node:path';
import {projectRoot} from './paths.mjs';

const args = process.argv.slice(2);
assert(args.length === 0 || (args.length === 2 && args[0] === '--root'), 'Usage: check-doc-links.mjs [--root <project>]');
const root = args.length ? path.resolve(args[1]) : projectRoot;
const files = ['README.md', 'GUIA_EJECUCION.md', 'TODO_SETUP.md', 'movil/README.md'];
async function collect(directory) {
  for (const entry of await readdir(path.join(root, directory), {withFileTypes:true})) {
    const relative = path.join(directory, entry.name);
    if (entry.isDirectory()) await collect(relative);
    else if (entry.name.endsWith('.md')) files.push(relative);
  }
}
await collect('docs');
await collect('scripts');
let links = 0;
const missing = [];
for (const relative of files) {
  const file = path.join(root, relative);
  const markdown = (await readFile(file, 'utf8')).replace(/^\s*```[^\n]*\n[\s\S]*?^\s*```\s*$/gm, '');
  for (const match of markdown.matchAll(/\[[^\]]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)/g)) {
    const target = match[1].replace(/^<|>$/g, '').split('#')[0];
    if (!target || /^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('//')) continue;
    links++;
    try { await stat(path.resolve(path.dirname(file), decodeURIComponent(target))); }
    catch { missing.push(`${relative}: ${target}`); }
  }
}
assert.equal(missing.length, 0, `Broken documentation links:\n${missing.join('\n')}`);
console.log(`Documentation verified: ${files.length} Markdown files, ${links} local links.`);
