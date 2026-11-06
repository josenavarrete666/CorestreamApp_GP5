import assert from 'node:assert/strict';
import {mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const projectRoot = fileURLToPath(new URL('../../', import.meta.url));

export async function artifactFile(name) {
  assert(/^[a-z0-9][a-z0-9.-]*$/.test(name), 'Use a simple artifact filename.');
  const directory = path.join(projectRoot, '.verification');
  await mkdir(directory, {recursive: true});
  return path.join(directory, name);
}
