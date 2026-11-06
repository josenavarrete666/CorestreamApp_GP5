import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {projectRoot} from './paths.mjs';

const args = process.argv.slice(2);
assert(args.length === 0 || (args.length === 2 && args[0] === '--temp-dir'), 'Usage: check-repository.mjs [--temp-dir <existing directory>]');
const temporary = await mkdtemp(path.join(args.length ? path.resolve(args[1]) : tmpdir(), 'corestream-repository-'));
function run(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {encoding:'utf8', maxBuffer:16 * 1024 * 1024, ...options});
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stderr || `${command} failed`);
  return result.stdout;
}
try {
  run('git', ['init', '--quiet', temporary]);
  const git = [`--git-dir=${path.join(temporary, '.git')}`, `--work-tree=${projectRoot}`];
  const candidates = run('git', [...git, 'ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean);
  const ignored = [
    '.env', '.env.local', '.pub-cache/package/file.dart', '.cache/file', '.verification/result.png', 'commands.txt',
    'backend/.local/manifest.json', 'backend/storage/document.pdf', 'backend/backups/data.sql',
    'backend/__pycache__/module.pyc', 'backend/.pytest_cache/result', 'backend/.mypy_cache/result',
    'backend/.ruff_cache/result', 'backend/.venv/bin/python', 'backend/htmlcov/index.html',
    'backend/.coverage.123', 'backend/coverage.xml', 'backend/module.egg-info/PKG-INFO',
    'movil/.dart_tool/package_config.json', 'movil/.flutter-plugins-dependencies', 'movil/build/web/index.html',
    'movil/android/local.properties', 'movil/android/.gradle/cache', 'movil/android/app/release/app.apk',
    'movil/android/key.properties', 'movil/android/app/key.jks', 'node_modules/package/index.js',
  ];
  const excluded = new Set(run('git', [...git, 'check-ignore', '--no-index', '-z', '--stdin'], {
    input:ignored.join('\0') + '\0',
  }).split('\0').filter(Boolean));
  for (const file of ignored) assert(excluded.has(file), `Expected an ignore rule for ${file}`);
  const required = [
    '.gitignore', '.gitattributes', '.env.example', 'docker-compose.yml', 'README.md', 'GUIA_EJECUCION.md', 'TODO_SETUP.md',
    'backend/.dockerignore', 'backend/.env.example', 'backend/Dockerfile', 'backend/alembic.ini',
    'backend/alembic/env.py', 'backend/migrations/create_indices_fix_003.sql', 'backend/requirements.txt',
    'backend/requirements-dev.txt', 'backend/pyproject.toml', 'backend/pytest.ini', 'backend/app/main.py',
    'backend/scripts/acceptance_beta.py', 'backend/tests/test_beta_tools.py', 'movil/.metadata',
    'movil/.gitignore', 'movil/pubspec.yaml', 'movil/pubspec.lock', 'movil/analysis_options.yaml',
    'movil/lib/main.dart', 'movil/test/widget_smoke_test.dart', 'movil/web/index.html',
    'scripts/init-env.ps1', 'scripts/start.ps1', 'scripts/start-flutter.ps1', 'scripts/serve-web.mjs',
    'scripts/verification/check-doc-links.mjs', 'scripts/verification/check-repository.mjs', 'scripts/verification/README.md', 'scripts/verification/edge-beta.mjs',
    'scripts/verification/edge-demo.mjs', 'scripts/verification/paths.mjs',
    'docs/estado-actual.md', 'docs/roles-permisos.md', 'docs/arranque-flutter.md',
    'docs/publicacion-github.md', 'docs/contratos-recorrido-inicial.json',
    'docs/requerimientos/CoreStream_App_Equipo1_Sesion_Seguridad_Plataforma.docx',
  ];
  const candidateSet = new Set(candidates);
  for (const file of required) assert(candidateSet.has(file), `Required source file is missing or ignored: ${file}`);
  const dockerIgnore = (await readFile(path.join(projectRoot, 'backend/.dockerignore'), 'utf8')).split(/\r?\n/);
  assert(dockerIgnore.includes('.local/'), 'Docker must exclude private manifests.');
  assert(dockerIgnore.includes('.env'), 'Docker must exclude local credentials.');

  const snapshot = path.join(temporary, 'snapshot');
  await mkdir(snapshot);
  for (const file of candidates) {
    assert(!/^\.\.(?:\/|\\)|^[A-Za-z]:|^\//.test(file), 'Invalid candidate path.');
    const destination = path.join(snapshot, file);
    await mkdir(path.dirname(destination), {recursive:true});
    await cp(path.join(projectRoot, file), destination);
  }
  run(process.execPath, [path.join(snapshot, 'scripts/verification/check-doc-links.mjs')]);
  for (const file of candidates.filter(file => /^scripts\/.*\.mjs$/.test(file))) {
    run(process.execPath, ['--check', path.join(snapshot, file)]);
  }
  console.log(JSON.stringify({candidateFiles:candidates.length, ignoredCases:ignored.length,
    requiredFiles:required.length, isolatedSnapshot:'passed', documentation:'passed', nodeSyntax:'passed'}, null, 2));
} finally {
  await rm(temporary, {recursive:true, force:true});
}
