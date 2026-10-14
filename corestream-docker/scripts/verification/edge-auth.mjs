import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {artifactFile, projectRoot} from './paths.mjs';

const port = Number(process.argv[2]), action = process.argv[3];
assert(Number.isInteger(port) && port > 0 && port < 65536, 'Pass an isolated Edge CDP port.');
assert(['visual', 'sessions', 'password'].includes(action), 'Choose visual, sessions or password.');
const fixturePath = path.resolve(projectRoot, process.env.CS_AUTH_FIXTURE ?? 'backend/.local/beta-content.json');
const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json());
const target = targets.find(t => t.type === 'page' && t.url.startsWith('http://localhost:7358/'));
assert(target, 'Flutter API page missing.');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, {once: true});
  socket.addEventListener('error', reject, {once: true});
});
let sequence = 0, mode = null;
const pending = new Map(), held = [], captures = [], requests = [], exceptions = [], checks = [];
const methods = new Map();
function command(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(Error(method)); }, 20000);
    pending.set(id, {resolve, reject, timer});
    socket.send(JSON.stringify({id, method, params}));
  });
}
socket.addEventListener('message', event => {
  const m = JSON.parse(event.data);
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id); clearTimeout(p.timer);
    m.error ? p.reject(Error(m.error.message)) : p.resolve(m.result);
  }
  if (m.method === 'Runtime.exceptionThrown') exceptions.push(m.params.exceptionDetails.text);
  if (m.method === 'Network.requestWillBeSent') methods.set(m.params.requestId, m.params.request.method);
  if (m.method === 'Network.responseReceived' && m.params.response.url.startsWith('http://localhost:8001/')) {
    const method = methods.get(m.params.requestId);
    if (method !== 'OPTIONS') requests.push({method, path: new URL(m.params.response.url).pathname, status: m.params.response.status});
  }
  if (m.method === 'Fetch.requestPaused') {
    if (m.params.request.method === 'OPTIONS') command('Fetch.continueRequest', {requestId: m.params.requestId}).catch(() => exceptions.push('Preflight interception failed'));
    else if (mode === 'hold') held.push(m.params.requestId);
    else command(mode === 'offline' ? 'Fetch.failRequest' : 'Fetch.continueRequest',
      {requestId: m.params.requestId, ...(mode === 'offline' ? {errorReason: 'InternetDisconnected'} : {})})
      .catch(() => exceptions.push('Interception failed'));
  }
});
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function evaluate(expression) {
  const r = await command('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  assert(!r.exceptionDetails, 'Browser evaluation failed.');
  return r.result.value;
}
async function state() {
  return evaluate(`(()=>({text:document.body.innerText,controls:[...document.querySelectorAll('flt-semantics,input,textarea')]
    .map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.innerText,tag:e.tagName,
      disabled:e.disabled,readOnly:e.readOnly,rect:e.getBoundingClientRect().toJSON()}))
    .filter(e=>e.rect.width>0&&e.rect.height>0)}))()`);
}
async function wait(text) {
  for (let i = 0; i < 120; i++) {
    await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
    const current = await state();
    if (current.text.includes(text) || current.controls.some(c => c.label?.includes(text))) return;
    await delay(150);
  }
  throw Error(`Expected UI: ${text}`);
}
async function click(rect) {
  for (const type of ['mousePressed', 'mouseReleased']) await command('Input.dispatchMouseEvent', {
    type, x: rect.x + rect.width / 2, y: rect.y + rect.height / 2, button: 'left', clickCount: 1,
  });
  await delay(300);
}
async function tap(text) {
  await wait(text);
  const items = (await state()).controls.filter(c => c.role === 'button' && (c.text === text || c.label === text));
  items.sort((a, b) => a.rect.width * a.rect.height - b.rect.width * b.rect.height);
  assert(items.length, `Button missing: ${text}`);
  const rect = items[0].rect, height = await evaluate('innerHeight');
  if (rect.y < 0 || rect.bottom > height) {
    await command('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 200, y: height / 2, deltaX: 0, deltaY: rect.y < 0 ? -400 : 400});
    await delay(400); return tap(text);
  }
  await click(rect);
}
async function fill(label, value) {
  await wait(label);
  const input = (await state()).controls.find(c => ['INPUT', 'TEXTAREA'].includes(c.tag) && c.label === label && !c.readOnly && !c.disabled);
  assert(input, `Input missing: ${label}`);
  await click(input.rect);
  await evaluate('document.activeElement.select()');
  await command('Input.insertText', {text: value});
}
async function capture(name) {
  await command('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 0, y: 0});
  await delay(200);
  const image = await command('Page.captureScreenshot', {format: 'png'});
  const file = await artifactFile(`8b5-${name}.png`);
  await writeFile(file, Buffer.from(image.data, 'base64'));
  captures.push(path.basename(file));
}
async function appearance(width = 390, dark = true, lang = 'es') {
  await command('Emulation.setDeviceMetricsOverride', {width, height: width === 390 ? 844 : 900, deviceScaleFactor: 1, mobile: false});
  await evaluate(`localStorage.setItem('flutter.dark', '${dark}');localStorage.setItem('flutter.lang', ${JSON.stringify(JSON.stringify(lang))});`);
  await command('Page.reload');
  await wait(lang === 'es' ? 'Ingresar' : 'Sign in');
}
async function signIn(credentials) {
  await fill('Correo electrónico', credentials.email);
  await fill('Contraseña', credentials.password);
  await tap('Ingresar');
}
async function signOut() { await tap('Ajustes'); await tap('Cerrar sesión'); await wait('Ingresar'); }
async function intercept(pattern, nextMode) {
  mode = nextMode;
  await command('Fetch.enable', {patterns: [{urlPattern: pattern, requestStage: 'Request'}]});
}
async function waitHeld() {
  for (let i = 0; i < 100 && !held.length; i++) await delay(100);
  assert(held.length, 'Expected paused request.');
  return held.shift();
}

try {
  await command('Page.enable'); await command('Runtime.enable'); await command('Network.enable');
  if (action === 'visual') {
    for (const width of [390, 1280]) for (const dark of [true, false]) for (const lang of ['es', 'en']) {
      await appearance(width, dark, lang);
      const name = `${width}-${dark ? 'dark' : 'light'}-${lang}`;
      const labels = lang === 'es' ? ['Ingresar', 'Correo electrónico', 'Contraseña', 'Introduce un correo válido.', 'Puedes volver a intentarlo']
        : ['Sign in', 'Email address', 'Password', 'Enter a valid email.', 'You can try again'];
      await capture(`${name}-login`);
      await tap(labels[0]); await wait(labels[3]); await capture(`${name}-validation`);
      await fill(labels[1], 'visual-check@example.com'); await fill(labels[2], 'Example123!');
      await tap(lang === 'es' ? 'Mostrar contraseña' : 'Show password'); await capture(`${name}-visible-example`);
      await tap(lang === 'es' ? 'Ocultar contraseña' : 'Hide password');
      await intercept('*localhost:8001/api/auth/login', 'hold');
      await tap(labels[0]); const requestId = await waitHeld(); await capture(`${name}-loading`);
      await command('Fetch.fulfillRequest', {requestId, responseCode: 429,
        responseHeaders: [{name: 'Content-Type', value: 'application/json'}, {name: 'Retry-After', value: '2'},
          {name: 'Access-Control-Allow-Origin', value: 'http://localhost:7358'}, {name: 'Access-Control-Allow-Credentials', value: 'true'},
          {name: 'Access-Control-Expose-Headers', value: 'Retry-After'}],
        body: Buffer.from(JSON.stringify({detail: lang === 'es' ? 'Demasiados intentos (verificación visual).' : 'Too many attempts (visual verification).'})).toString('base64')});
      await wait(labels[4]); await capture(`${name}-429-injected`);
      await command('Fetch.disable'); mode = null;
      checks.push({configuration: name, states: 5, rate_limit_source: 'CDP response injection'});
    }
  }
  if (action === 'sessions') {
    const data = JSON.parse(await readFile(fixturePath, 'utf8'));
    assert.equal(data.purpose, 'beta-content'); assert.equal(data.state, 'active');
    await appearance();
    await fill('Correo electrónico', 'invalid-auth-check@example.com'); await fill('Contraseña', 'InvalidExample123!');
    await tap('Ingresar'); await wait('Email o contraseña incorrectos'); await capture('credentials-rejected-real');
    for (const [role, key] of [['admin', 'admin'], ['leader', 'u2'], ['developer', 'u3']]) {
      await signIn(data.users[key]); await wait('Tiempo real conectado'); await capture(`${role}-authenticated-real`);
      await intercept('*localhost:8001/api/auth/refresh', 'hold');
      await command('Page.reload'); await wait('Recuperando sesión');
      const requestId = await waitHeld(); await capture(`${role}-restoring`);
      await command('Fetch.continueRequest', {requestId}); await command('Fetch.disable'); mode = null;
      await wait('Tiempo real conectado');
      await signOut(); await wait('Sesión cerrada y revocación confirmada'); await capture(`${role}-signed-out-real`);
      checks.push({role, login: 'real API', restoration: 'real refresh, paused for capture', logout: 'real API'});
    }
    await signIn(data.users.u3); await wait('Tiempo real conectado');
    await intercept('*localhost:8001/*', 'offline');
    await tap('Ajustes'); await tap('Cerrar sesión'); await wait('Confirmar cierre con el servidor');
    await capture('logout-pending-network-injected');
    await command('Page.reload'); await wait('Confirmar cierre con el servidor');
    assert(!(await state()).controls.some(c => c.tag === 'INPUT' && c.label === 'Correo electrónico'));
    await capture('logout-pending-after-reload');
    await command('Fetch.disable'); mode = null;
    await tap('Confirmar cierre con el servidor'); await wait('Ingresar');
    await capture('logout-pending-recovered-real');
    checks.push({pending_logout: 'survives reload; real server recovery', failure_source: 'CDP API transport injection'});
  }
  if (action === 'password') {
    const data = JSON.parse(await readFile(fixturePath, 'utf8'));
    assert(data.run_id && data.ids?.other && data.users?.other, 'Fresh stage8 acceptance fixture required.');
    const credential = data.users.other;
    const nextPassword = randomBytes(24).toString('base64url') + 'Aa1!';
    await appearance(); await signIn(credential); await wait('Actualiza tu contraseña');
    await capture('password-required-real');
    await fill('Contraseña actual', credential.password); await fill('Nueva contraseña', nextPassword);
    await fill('Confirmar nueva contraseña', 'MismatchExample123!');
    await tap('Cambiar y volver a ingresar'); await wait('Las contraseñas no coinciden');
    await capture('password-mismatch');
    await fill('Confirmar nueva contraseña', nextPassword);
    await tap('Cambiar y volver a ingresar'); await wait('Sesión cerrada y revocación confirmada');
    // Persist the changed test credential locally so verification/recovery can resume.
    credential.password = nextPassword;
    await writeFile(fixturePath, JSON.stringify(data, null, 2), {mode: 0o600});
    await capture('password-changed-signed-out-real');
    await signIn(credential); await wait('Tiempo real conectado'); await capture('password-new-login-real');
    await signOut();
    checks.push({temporary_user: data.ids.other, password_change: 'real API', new_login: 'real API', logout: 'real API'});
  }
  assert.equal(exceptions.length, 0, 'Browser runtime exceptions.');
  const report = await artifactFile(`8b5-${action}-report.json`);
  await writeFile(report, JSON.stringify({date: new Date().toISOString(), action, captures, checks, requests, exceptions}, null, 2));
  console.log(JSON.stringify({action, captures: captures.length, checks, exceptions: 0, report}, null, 2));
} finally {
  mode = null;
  for (const requestId of held) await command('Fetch.continueRequest', {requestId}).catch(() => {});
  await command('Fetch.disable').catch(() => {});
  socket.close();
}
