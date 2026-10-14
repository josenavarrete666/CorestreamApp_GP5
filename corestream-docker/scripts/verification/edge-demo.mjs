import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { artifactFile } from './paths.mjs';

const port = Number(process.argv[2]);
const action = process.argv[3] ?? 'state';
assert(Number.isInteger(port) && port > 0 && port < 65536, 'Pass the Edge debug port.');
const targets = await fetch(`http://127.0.0.1:${port}/json/list`).then(r => r.json());
const target = targets.find(t => t.type === 'page' && /^http:\/\/(localhost|127\.0\.0\.1):7358\//.test(t.url));
assert(target, 'Expected the Flutter demo page on port 7358.');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});
let nextId = 0;
const pending = new Map();
const errors = [];
socket.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
  if (message.id) {
    const request = pending.get(message.id);
    if (request) {
      clearTimeout(request.timer);
      pending.delete(message.id);
      if (message.error) request.reject(new Error(JSON.stringify(message.error)));
      else request.resolve(message.result);
    }
  }
});
function command(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(expression) {
  const result = await command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  assert(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function state() {
  return evaluate(`(() => ({url:location.href, title:document.title, text:document.body.innerText,
    controls:[...document.querySelectorAll('[role="button"],button,[role="tab"],[role="switch"]')].map(e=>{
      const r=e.getBoundingClientRect(); return {tag:e.tagName,role:e.getAttribute('role'),
      label:e.getAttribute('aria-label'),text:e.innerText,checked:e.getAttribute('aria-checked'),
      rect:{x:r.x,y:r.y,width:r.width,height:r.height}};
    })}))()`);
}
async function tap(label) {
  const controls = (await state()).controls.filter(c =>
    c.rect.width > 0 && c.rect.height > 0 && `${c.label ?? ''} ${c.text ?? ''}`.includes(label));
  assert.equal(controls.length, 1, `Expected one control for ${label}: ${JSON.stringify(controls)}`);
  const rect = controls[0].rect;
  const x = rect.x + rect.width / 2;
  const y = rect.y + rect.height / 2;
  await point(x, y);
}
async function point(x, y) {
  assert(Number.isFinite(x) && Number.isFinite(y), 'Pass numeric viewport coordinates.');
  const size = await evaluate('({width:innerWidth,height:innerHeight})');
  assert(x >= 0 && y >= 0 && x < size.width && y < size.height, 'Point must be inside the viewport.');
  await command('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  await delay(700);
}
async function screenshot(name) {
  assert(/^[a-z0-9-]+$/.test(name), 'Pass a simple screenshot name.');
  const image = await command('Page.captureScreenshot', { format: 'png' });
  const path = await artifactFile(`stage6-${name}.png`);
  await writeFile(path, Buffer.from(image.data, 'base64'), { flag: 'wx' });
  console.log(JSON.stringify({ screenshot: path }));
}
async function reload() {
  await command('Page.reload');
  for (let attempt = 0; attempt < 30; attempt++) {
    await delay(500);
    await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
    if ((await state()).text.includes('Selecciona un usuario demo')) return;
  }
  assert.fail('Demo login did not render after reload.');
}
try {
  await command('Runtime.enable');
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await delay(700);
  if (action === 'tap') await tap(process.argv[4]);
  if (action === 'point') await point(Number(process.argv[4]), Number(process.argv[5]));
  if (action === 'reload') await reload();
  if (action === 'screenshot') await screenshot(process.argv[4]);
  if (action === 'walk') {
    for (const token of process.argv.slice(4)) {
      const [label, image] = token.split('=');
      const step = { tap: label, screenshot: image };
      if (step.tap) await tap(step.tap);
      if (step.screenshot) await screenshot(step.screenshot);
      const current = await state();
      if (step.expect) assert(current.text.includes(step.expect), `Missing ${step.expect}: ${current.text}`);
      console.log(JSON.stringify({ step, text: current.text,
        controls: current.controls.map(c => c.label || c.text) }));
    }
  }
  if (action === 'simulate') {
    const prefix = process.argv[4] ?? 'simulation';
    assert(/^[a-z0-9-]+$/.test(prefix), 'Pass a simple simulation evidence name.');
    await reload();
    await tap('Ana Torres');
    const before = await state();
    assert(before.text.includes('Notificaciones 2'), before.text);
    await screenshot(`${prefix}-before`);
    console.log(JSON.stringify({ phase: 'before', text: before.text }));
    await delay(21000);
    const after = await state();
    assert(after.text.includes('Notificaciones 3'), after.text);
    assert(after.text.includes('CORESTREAM · AHORA Nueva incidencia'), after.text);
    await screenshot(`${prefix}-event`);
    console.log(JSON.stringify({ phase: 'after', text: after.text }));
    await delay(6000);
    await tap('Notificaciones');
    const notifications = await state();
    assert(notifications.text.startsWith('Back\nNotificaciones\n'), notifications.text);
    assert(notifications.text.includes('Error 500 al exportar'), notifications.text);
    await screenshot(`${prefix}-notifications`);
    console.log(JSON.stringify({ phase: 'notifications', text: notifications.text }));
    await tap('Back');
    await tap('Ajustes');
    await tap('Cerrar sesión');
    assert((await state()).text.includes('Datos de demostración'), 'Logout did not return to demo login.');
    await screenshot(`${prefix}-logout`);
  }
  assert.equal(errors.length, 0, `Browser runtime exceptions: ${JSON.stringify(errors)}`);
  console.log(JSON.stringify(await state(), null, 2));
} finally {
  socket.close();
}
