import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {artifactFile, projectRoot} from './paths.mjs';

const port=Number(process.argv[2]), action=process.argv[3]??'state';
assert(Number.isInteger(port) && port > 0 && port < 65536, 'Pass the Edge debug port.');
const fixtureFile=path.resolve(projectRoot, process.env.CS_BETA_FIXTURE ?? 'backend/.local/beta-manual.json');
const fixture=async()=>JSON.parse(await readFile(fixtureFile,'utf8'));
const targets=await fetch(`http://127.0.0.1:${port}/json/list`).then(r=>r.json());
const target=targets.filter(t=>t.type==='page'&&/^http:\/\/localhost:7358\//.test(t.url)).at(-1);
assert(target,'Flutter Edge target missing');
const socket=new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
let sequence=0;
const pending=new Map(), requests=[], exceptions=[], methods=new Map(), creations=[], responses=new Map(), frames=[];
socket.addEventListener('message',async event=>{
  const m=JSON.parse(event.data);
  if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}
  if(m.method==='Runtime.exceptionThrown'){const d=m.params.exceptionDetails;exceptions.push({message:(d.exception?.description??d.text).slice(0,2500),url:d.url,frames:d.stackTrace?.callFrames.map(f=>({function:f.functionName,url:f.url,line:f.lineNumber}))});}
  if(m.method==='Network.requestWillBeSent')methods.set(m.params.requestId,m.params.request.method);
  if(m.method==='Network.webSocketFrameReceived'){try{const f=JSON.parse(m.params.response.payloadData);frames.push({type:f.type,id:f.data?.id});}catch{}}
  if(m.method==='Network.responseReceived'&&m.params.response.url.startsWith('http://localhost:8001/')){
    const record={method:methods.get(m.params.requestId),path:new URL(m.params.response.url).pathname,status:m.params.response.status};
    if(record.method!=='OPTIONS')requests.push(record);
    if(record.method==='POST'&&record.path==='/api/tickets/'&&record.status===201)responses.set(m.params.requestId,record);
  }
  if(m.method==='Network.loadingFinished'&&responses.has(m.params.requestId)){const raw=JSON.parse((await command('Network.getResponseBody',{requestId:m.params.requestId})).body);creations.push({id:raw.id,epic:raw.epic_id});}
});
function command(method,params={}){return new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>reject(Error(method)),15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});}
async function evaluate(expression){const r=await command('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert(!r.exceptionDetails,`Evaluation failed: ${r.exceptionDetails?.exception?.description??r.exceptionDetails?.text}`);return r.result.value;}
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function state(){return evaluate(`(()=>({viewport:{width:innerWidth,height:innerHeight},text:[document.body.innerText,...[...document.querySelectorAll('flt-semantics[aria-label]')].map(e=>e.getAttribute('aria-label'))].join(String.fromCharCode(10)),
  controls:[...document.querySelectorAll('flt-semantics,[role="button"],button,input,textarea')].filter(e=>e.getBoundingClientRect().width>0).map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),placeholder:e.getAttribute('placeholder'),readOnly:e.readOnly,text:e.innerText,tag:e.tagName,rect:e.getBoundingClientRect().toJSON()}))}))()`);}
async function wait(text){for(let i=0;i<100;i++){await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);const s=await state();if(s.text.includes(text)||s.controls.some(e=>e.label?.includes(text)||e.placeholder?.includes(text)))return;await delay(200);}throw Error(`Expected UI: ${text}`);}
async function click(rect){const x=rect.x+rect.width/2,y=rect.y+rect.height/2;await command('Input.dispatchMouseEvent',{type:'mousePressed',x,y,button:'left',clickCount:1});await command('Input.dispatchMouseEvent',{type:'mouseReleased',x,y,button:'left',clickCount:1});await delay(300);}
async function tap(label){for(let i=0;i<30;i++){const items=(await state()).controls.filter(e=>(e.label===label||e.text===label)&&e.rect.height>0&&e.role==='button');if(!items.length){await delay(200);continue;}items.sort((a,b)=>a.rect.width*a.rect.height-b.rect.width*b.rect.height);const rect=items[0].rect;assert(items.every(e=>e.rect.x<=rect.x&&e.rect.y<=rect.y&&e.rect.right>=rect.right&&e.rect.bottom>=rect.bottom),`Ambiguous button ${label}`);const height=await evaluate('innerHeight');if(rect.y+rect.height/2>height||rect.y<0){await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:height/2,deltaX:0,deltaY:rect.y<0?-400:400});await delay(300);continue;}await click(rect);return;}throw Error(`Button unavailable: ${label}`);}
async function textTap(label){for(let i=0;i<30;i++){const items=(await state()).controls.filter(e=>(e.label??'').includes(label)||e.text?.includes(label)).filter(e=>e.rect.height>0&&e.rect.y>=0);items.sort((a,b)=>Number(b.label===label||b.text===label)-Number(a.label===label||a.text===label)||a.rect.width*a.rect.height-b.rect.width*b.rect.height);if(items.length){await click(items[0].rect);await delay(400);return;}await delay(100);}throw Error(`Text missing: ${label}`);}
async function project(){const data=await fixture();const items=(await state()).controls.filter(e=>`${e.label??''} ${e.text??''}`.includes(data.run_id)&&!`${e.label??''} ${e.text??''}`.includes('Vacía'));items.sort((a,b)=>a.rect.width*a.rect.height-b.rect.width*b.rect.height);assert(items.length,'Main project missing');await click(items[0].rect);await wait('Entrega y revisión');}
async function fill(label,value){const inputs=(await state()).controls.filter(e=>['INPUT','TEXTAREA'].includes(e.tag)&&!e.readOnly);const matching=inputs.filter(e=>e.label===label||e.placeholder===label);const items=matching.length?matching:inputs;assert(items.length===1,`Expected input ${label}`);await click(items[0].rect);await evaluate(`document.activeElement.select()`);await command('Input.insertText',{text:value});}
async function login(role){const data=await fixture();await wait('Ingresar');await fill('Correo electrónico',data.users[role].email);await fill('Contraseña',data.users[role].password);await tap('Ingresar');await wait('Tiempo real conectado');}
async function logout(){for(let i=0;i<80;i++){await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);const current=await state();if(current.text.includes('Ingresar'))return;if(current.controls.some(e=>(e.text??e.label)==='Ajustes')){await tap('Ajustes');await tap('Cerrar sesión');await wait('Ingresar');return;}if(current.controls.some(e=>(e.text??e.label)==='Back')){await tap('Back');await delay(500);}else await delay(200);}throw Error('Could not return to settings');}
async function capture(name){assert(/^[a-z0-9-]+$/.test(name));const image=await command('Page.captureScreenshot',{format:'png'});const file=await artifactFile(`beta-${name}.png`);await writeFile(file,Buffer.from(image.data,'base64'));return file;}
async function createTicket(){
   const buttons=(await state()).controls.filter(e=>e.role==='button'&&(e.text==='Nuevo ticket'||e.label==='Nuevo ticket')).sort((a,b)=>a.rect.y-b.rect.y);
   assert(buttons.length,'New ticket button');assert(buttons[0].rect.bottom<=(await evaluate('innerHeight')),'First epic create button must be visible');
   await click(buttons[0].rect);await wait('Se creará en esta épica');
  await fill('Título del ticket','Ticket preparado para recorrido manual');await tap('Guardar');await wait('Ticket preparado para recorrido manual');
  for(let i=0;i<30&&!creations.length;i++)await delay(100);
  const data=await fixture();
  assert.equal(creations.length,1,'One persisted creation');assert.equal(creations[0].epic,data.ids.epic);data.tracked_tickets.push(creations[0].id);await writeFile(fixtureFile,JSON.stringify(data,null,2));
}
try{
  if(process.argv.includes('--report'))await command('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false});
   if(action==='close'){
     const closed=new Promise(resolve=>socket.addEventListener('close',resolve,{once:true}));
     await Promise.race([command('Browser.close'),closed]);
     for(const item of pending.values())clearTimeout(item.timer);
     pending.clear();console.log('Isolated acceptance browser closed');
   }else{
  await command('Page.bringToFront');
  await command('Page.enable');await command('Runtime.enable');await command('Network.enable');
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);await delay(400);
  const baselineExceptions=exceptions.splice(0);
  if(action==='login')await login(process.argv[4]??'developer');
  if(action==='switch'){await logout();await login(process.argv[4]);}
  if(action==='logout')await logout();
  if(action==='resume'){await tap('Reanudar trabajo');await wait('Describe cómo se resolvió');await fill('…','Verificar el dato persistente después de recargar.');await tap('Reanudar trabajo');await wait('En progreso');}
  if(action==='complete'){await tap('Completar');await wait('El enlace de Pull Request es opcional');await tap('Completar');await wait('Hecho');}
  if(action==='read-suite'){
    const data=await fixture();
    for(const role of ['admin','leader','developer']){
      await logout();await login(role);await delay(1000);
      await capture(`${role}-home`);
      await textTap('Proyectos');await wait(data.run_id);await capture(`${role}-projects`);
      await project();await capture(`${role}-board`);await tap('Back');
      await textTap('Incidencias');await wait('Incidente mitigated');await capture(`${role}-incidents`);
      await textTap('Incidente mitigated');await wait('Alternativa temporal aplicada');await capture(`${role}-incident-detail`);await tap('Back');
      if(role!=='developer'){await textTap('Equipo');await wait('Beta Colaborador');await capture(`${role}-team`);}
      await tap('Ajustes');await capture(`${role}-settings`);
      await command('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await command('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await delay(300);
    }
  }
  if(action==='new-ticket'){
    await createTicket();
  }
   if(action==='operations'){
     await command('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false});
    await textTap('Proyectos');await project();await createTicket();await textTap('Ticket preparado para recorrido manual');await wait('Asignar');await tap('Asignar');await textTap('Beta Desarrollador');await tap('Confirmar');await wait('Reasignar');await capture('created-assigned');
    await logout();await login('developer');await textTap('Proyectos');await project();await textTap('Ticket preparado para recorrido manual');
  }
  if(action==='operations'||action==='ticket-cycle'){
    await wait('Comenzar');await tap('Comenzar a trabajar');await wait('Plantear pregunta');await tap('Plantear pregunta');await wait('Enviar');await fill('','¿Cómo confirmar el recorrido de interfaz integrado?');await tap('Enviar');await wait('Bloqueado');await capture('question-work-paused');
    await logout();await login('leader');await textTap('Proyectos');await project();await textTap('Ticket preparado para recorrido manual');await wait('Reanudar trabajo');await tap('Reanudar trabajo');await wait('Describe cómo se resolvió');await fill('…','Reconsultar estado, historial y persistencia de la operación.');await tap('Reanudar trabajo');await wait('En progreso');
    await logout();await login('developer');await textTap('Proyectos');await project();await textTap('Ticket preparado para recorrido manual');await wait('Completar');await tap('Completar');await wait('El enlace de Pull Request es opcional');await tap('Completar');await wait('Hecho');await capture('completed-no-pr');await tap('Back');
    await textTap('Implementar integración beta');await wait('Verificar contrato HTTP');await textTap('Verificar contrato HTTP');await wait('SUBTAREAS · 1/2');await capture('subtask-persisted');await tap('Back');
    await textTap('Trabajo en progreso');await wait('Redirigir');await tap('Redirigir');await wait('Razón');await textTap('Beta Colaborador');await fill('Razón (mín. 10 caracteres)','Traspaso justificado para completar la aceptación en Edge.');await tap('Confirmar');await wait('Trabajo en progreso');await capture('redirected-board');
    assert(requests.some(r=>r.method==='POST'&&r.path.endsWith('/redirect')&&r.status===200));
  }
  if(action==='incident-operations'){
    await logout();await login('admin');await textTap('Incidencias');await textTap('Incidente reported');await wait('Asignar');await tap('Asignar');await textTap('Beta Desarrollador');await tap('Confirmar');await wait('Beta Desarrollador');await capture('incident-assigned');
    await logout();await login('developer');await textTap('Incidencias');await textTap('Incidente reported');
  }
  if(action==='incident-operations'||action==='incident-status'){
    await wait('Cambiar estado');const combo=(await state()).controls.find(e=>e.label?.startsWith('Cambiar estado'));assert(combo);await click({...combo.rect,height:40});await textTap('Investigando');await tap('Guardar');await delay(1000);await capture('incident-updated');
    assert(requests.some(r=>r.method==='PATCH'&&r.path.endsWith('/status')&&r.status===200));
  }
  if(action==='redirect-submit'){await textTap('Beta Colaborador');await fill('Razón (mín. 10 caracteres)','Traspaso justificado para completar la aceptación en Edge.');await tap('Confirmar');await wait('Trabajo en progreso');await capture('redirected-board');assert(requests.some(r=>r.method==='POST'&&r.path.endsWith('/redirect')&&r.status===200));}
  if(action==='visual-suite'){
    for(const [width,height] of [[390,844],[1280,900]]){
      await command('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      for(const role of ['admin','leader','developer']){
        await logout();await login(role);await delay(1500);await capture(`${role}-${width}-dark-es-home`);
        await textTap('Proyectos');await wait('Vacía');await textTap('Vacía');await wait('Este proyecto aún no tiene épicas');await capture(`${role}-${width}-empty-project`);await tap('Back');
        await tap('Ajustes');await capture(`${role}-${width}-dark-es-settings`);await textTap('Claro');await textTap('English');await wait('Settings');await capture(`${role}-${width}-light-en-settings`);
        await command('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await command('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await delay(400);await capture(`${role}-${width}-light-en-projects`);
        await textTap('Incidents');await wait('Mitigated');await capture(`${role}-${width}-light-en-incidents`);await tap('Settings');await textTap('Español');await textTap('Oscuro');
        await command('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await command('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await delay(400);
      }
    }
  }
  if(action==='identity-suite'){
    const data=await fixture();
    assert.equal(data.purpose,'beta-content','Identity checks require the persistent beta-content manifest');
    assert.equal(data.state,'active');
    const seed=JSON.parse(await readFile(path.join(projectRoot,'backend/scripts/beta_content_seed.json'),'utf8'));
    const dismiss=async()=>{await command('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await command('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await delay(400);};
    for(const [width,height] of [[390,844],[1280,900]]){
      await command('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      await delay(600);
      for(const [role,key,alias] of [['admin','admin','u1'],['leader','u2','u2'],['developer','u3','u3']]){
        await logout();await login(key);await delay(800);
        await textTap('Proyectos');await wait('Portal Clientes');
        const projects=await state();
        for(const app of seed.applications){assert(projects.text.includes(app.name));assert(projects.text.includes(app.icon));}
        await capture(`8b4-${role}-${width}-projects`);
        if(role!=='developer'){
          await textTap('Equipo');await wait('Backend · Líder equipo Pagos');
          const team=await state();
          for(const person of seed.users.filter(u=>u.role!=='ADMIN'))assert(team.text.includes(person.specialty));
          await capture(`8b4-${role}-${width}-team`);
          await textTap('Proyectos');
        }
        await tap('Ajustes');await wait(seed.users.find(u=>u.alias===alias).full_name);
        await capture(`8b4-${role}-${width}-settings`);await dismiss();
        await textTap('Portal Clientes');await wait(seed.epics.find(e=>e.alias==='e1').title);
        await textTap(seed.tickets.find(t=>t.alias==='t1').title);await wait('Diego Ramos');
        await capture(`8b4-${role}-${width}-ticket`);
        const selectAction=role==='developer'?'Redirigir':'Reasignar';
        for(let i=0;i<8&&!(await state()).controls.some(e=>e.role==='button'&&(e.label===selectAction||e.text===selectAction));i++){
          await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:height/2,deltaX:0,deltaY:400});await delay(300);
        }
        await tap(selectAction);await wait('Backend · Líder equipo Pagos');
        await capture(`8b4-${role}-${width}-selector`);await dismiss();await tap('Back');await delay(600);await tap('Back');await delay(600);
      }
    }
    await logout();
    assert(!requests.some(r=>['PUT','PATCH','DELETE'].includes(r.method)||
      r.method==='POST'&&!['/api/auth/login','/api/auth/logout','/api/auth/refresh','/api/auth/ws-ticket'].includes(r.path)),
      'Identity checks must not mutate content');
  }
   if(action==='acceptance-suite'){
     const data=await fixture();assert.equal(data.purpose,'beta-content');assert.equal(data.state,'active');
     const seed=JSON.parse(await readFile(path.join(projectRoot,'backend/scripts/beta_content_seed.json'),'utf8'));
     const title=seed.tickets.find(t=>t.alias==='t7').title;
     const report=await artifactFile('8b8-acceptance-report.json');
     const prior=process.argv.includes('--resume')?JSON.parse(await readFile(report,'utf8')):{cases:[],captures:[],requests:[]};
     assert.equal(prior.exceptions?.length??0,0);
     const cases=[...prior.cases],captures=[...prior.captures];requests.push(...prior.requests);
     const appearance=async(dark,lang)=>{
       await evaluate(`localStorage.setItem('flutter.dark','${dark}');localStorage.setItem('flutter.lang',${JSON.stringify(JSON.stringify(lang))});`);
       await command('Page.reload');await wait(lang==='es'?'Ajustes':'Settings');await delay(400);
     };
     const shot=async(name)=>{await command('Input.dispatchMouseEvent',{type:'mouseMoved',x:0,y:0});captures.push(path.basename(await capture(`8b8-${name}`)));};
     const open=async(text)=>{
       for(let i=0;i<20;i++){
         const s=await state();const item=s.controls.filter(e=>e.role==='button'&&`${e.text??''} ${e.label??''}`.includes(text)&&e.rect.y>=0&&e.rect.bottom<=s.viewport.height).sort((a,b)=>a.rect.width*a.rect.height-b.rect.width*b.rect.height)[0];
         if(item){await click(item.rect);return;}
         await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:s.viewport.height/2,deltaX:0,deltaY:200});await delay(200);
       }
       throw Error(`Semantic card missing: ${text}`);
     };
     for(const [width,height] of [[390,844],[1280,900]])for(const [role,key] of [['admin','admin'],['leader','u2'],['developer','u3']]){
       await evaluate(`localStorage.setItem('flutter.dark','true');localStorage.setItem('flutter.lang','"es"');`);
       await command('Page.reload');await delay(1000);await logout();await login(key);
       await command('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
       for(const dark of [true,false])for(const lang of ['es','en']){
         if(cases.some(c=>c.role===role&&c.width===width&&c.dark===dark&&c.lang===lang))continue;
         await appearance(dark,lang);assert.deepEqual((await state()).viewport,{width,height});
         const en=lang==='en',prefix=`${role}-${width}-${dark?'dark':'light'}-${lang}`;
         const missing=dark===en;
         await wait('Portal Clientes');await shot(`${prefix}-home`);
         await textTap(en?'Projects':'Proyectos');await wait('API Pagos');if(missing)await shot(`${prefix}-projects`);await open('API Pagos');await wait('Webhooks de pago');
         await open(title);await wait(en?'DESCRIPTION':'DESCRIPCIÓN');assert((await state()).text.includes(title));await shot(`${prefix}-ticket`);
         await tap('Back');await delay(400);await shot(`${prefix}-board`);await tap('Back');await delay(400);
         if(missing){
           await open('Portal Clientes');await wait('Autenticación y seguridad');await shot(`${prefix}-portal-board`);
           await open(seed.tickets.find(t=>t.alias==='t1').title);await wait(en?'DESCRIPTION':'DESCRIPCIÓN');
           await open(role==='developer'?(en?'Complete':'Completar'):(en?'Reassign':'Reasignar'));
           await wait(role==='developer'?(en?'The Pull Request link is optional':'El enlace de Pull Request es opcional'):'Backend · Líder equipo Pagos');
           await shot(`${prefix}-panel`);
           for(const type of ['keyDown','keyUp'])await command('Input.dispatchKeyEvent',{type,key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
           await delay(300);await tap('Back');await delay(300);await tap('Back');await delay(300);
           await textTap(en?'Incidents':'Incidencias');await wait(seed.incidents[0].title);await open(seed.incidents[0].title);await wait(en?'Reported by':'Reportada por');await shot(`${prefix}-incident`);
           await tap('Back');await delay(300);
           if(role!=='developer'){await textTap(en?'Team':'Equipo');await wait('Backend · Líder equipo Pagos');await shot(`${prefix}-team`);}
         }
         await tap(en?'Settings':'Ajustes');await wait(data.users[key].email);await shot(`${prefix}-settings`);
         for(const type of ['keyDown','keyUp'])await command('Input.dispatchKeyEvent',{type,key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
         await delay(400);
         const countButtons=(await state()).controls.filter(e=>e.role==='button'&&(e.text??e.label??'').startsWith(en?'Notifications':'Notificaciones'));
         assert(countButtons.length);await click(countButtons[0].rect);await wait(en?'Notifications':'Notificaciones');await shot(`${prefix}-notifications`);await tap('Back');await delay(300);
         cases.push({role,width,height,dark,lang,semanticTicket:true,extendedScreens:missing});
         assert.equal(exceptions.length,0);
         await writeFile(report,JSON.stringify({date:new Date().toISOString(),complete:false,cases,captures,requests,exceptions},null,2));
         console.log(JSON.stringify({case:prefix,captures:captures.filter(n=>n.includes(prefix)).length}));
       }
     }
     await appearance(true,'es');await logout();
     assert.equal(cases.length,24);assert.equal(exceptions.length,0);
     assert(!requests.some(r=>['PUT','PATCH','DELETE'].includes(r.method)||r.method==='POST'&&!['/api/auth/login','/api/auth/logout','/api/auth/refresh','/api/auth/ws-ticket'].includes(r.path)));
     await writeFile(report,JSON.stringify({date:new Date().toISOString(),complete:true,cases,captures,requests,exceptions,contentWrites:0},null,2));
     console.log(JSON.stringify({cases:24,captures:captures.length,report,contentWrites:0}));
   }
   if(action==='interaction-check'){
     const data=await fixture();assert.equal(data.purpose,'beta-development');
     const reset=async()=>{await command('Page.reload');await wait('Tiempo real conectado');await wait('Beta Desarrollador');await delay(600);};
     const notificationButton=async()=>{
       const button=(await state()).controls.find(e=>e.role==='button'&&(e.text??e.label??'').startsWith('Notificaciones'));
       assert(button);await click(button.rect);await wait('Notificaciones');await delay(400);
     };
     const emit=async(support=false)=>{
       const relative=path.relative(path.join(projectRoot,'backend'),fixtureFile);
       assert(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative));
       const result=await promisify(execFile)('wsl',['-d','Ubuntu-24.04','-u','root','--cd',projectRoot,'--exec','/usr/bin/docker','compose','exec','-T','backend','python','-m',support?'scripts.acceptance_beta':'scripts.acceptance_stage8',support?'support-event':'event',data.run_id,'--local-file',`/app/${relative.split(path.sep).join('/')}`]);
       const event=JSON.parse(result.stdout);assert(event.published);return event;
     };
     await reset();assert(!(await state()).controls.some(e=>e.role==='tab'&&e.label==='Equipo'));
     try{
       await command('Network.emulateNetworkConditions',{offline:true,latency:0,downloadThroughput:0,uploadThroughput:0});
       await tap('Actualizar');await wait('No se pudo conectar');await capture('8b7-network-error');
     }finally{await command('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});}
     await tap('Reintentar');await wait('Implementar integración beta');assert(!(await state()).text.includes('No se pudo conectar'));
     await capture('8b7-network-recovered');
     await emit();await wait('Evento WS real');await capture('8b7-live-toast');
     await textTap('Evento WS real');await wait('DESCRIPCIÓN');assert((await state()).text.includes('Implementar integración beta'));
     await reset();await notificationButton();await textTap('Evento WS real');await wait('DESCRIPCIÓN');
     await capture('8b7-notification-ticket');assert(requests.some(r=>r.path==='/api/notifications/mark-read'&&r.method==='POST'&&r.status===200));
     await reset();await emit(true);await wait('Notificación de soporte');await delay(5500);
     await notificationButton();await textTap('Notificación de soporte');await wait('este detalle admite tickets DEVELOPMENT');
     assert(!(await state()).text.includes('DESCRIPCIÓN'));await capture('8b7-support-separated');
     await tap('Marcar todas como leídas');await delay(600);await tap('Back');await wait('Ajustes');
     assert((await state()).controls.some(e=>e.role==='button'&&(e.text??e.label)==='Notificaciones'));
     await reset();assert((await state()).controls.some(e=>e.role==='button'&&(e.text??e.label)==='Notificaciones'));
     await textTap('Proyectos');await project();await textTap('Implementar integración beta');await wait('DESCRIPCIÓN');
     await logout();assert(!(await state()).text.includes('Implementar integración beta'));
     await login('leader');await wait('Hola, Beta');
     assert(!(await state()).controls.some(e=>e.role==='button'&&(e.text??e.label)==='Back'));
     await capture('8b7-session-switched');await logout();await command('Page.reload');await wait('Ingresar');
     assert(!(await state()).text.includes('Tiempo real conectado'));
     console.log(JSON.stringify({networkRecovery:true,toastNavigation:true,individualRead:true,allReadPersisted:true,supportSeparated:true,sessionIsolation:true}));
   }
   if(action==='board-check'){
     await command('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
     await textTap('Proyectos');await wait('API Pagos');await textTap('API Pagos');await wait('Conciliación bancaria');
     const title='Reintentos exponenciales en webhooks fallidos';
     let card;
     for(let i=0;i<12&&!card;i++){
       const current=await state();
       card=current.controls.find(e=>e.role==='button'&&`${e.text??''} ${e.label??''}`.includes(title)&&e.rect.y>=0&&e.rect.bottom<=844);
       if(!card){await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:420,deltaX:0,deltaY:180});await delay(500);}
     }
     await capture('8b7-board-semantics');
     assert(card,'Second epic ticket must be exposed as a visible semantic button');
     let focused=false;
     for(let i=0;i<24&&!focused;i++){
       for(const type of ['keyDown','keyUp'])await command('Input.dispatchKeyEvent',{type,key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
       await delay(100);focused=await evaluate(`document.activeElement?.innerText?.includes(${JSON.stringify(title)})??false`);
     }
     assert(focused,'Second epic ticket must be reachable with Tab');
     for(const type of ['keyDown','keyUp'])await command('Input.dispatchKeyEvent',{type,key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
     await wait('DESCRIPCIÓN');assert((await state()).text.includes(title));
     const report={date:new Date().toISOString(),semanticButton:true,keyboard:'Tab/Enter',correctTicket:true,exceptions};
     await writeFile(await artifactFile('8b7-board-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
   }
   if(action==='screens-suite'){
    const data=await fixture();
    assert.equal(data.purpose,'beta-content');assert.equal(data.state,'active');
    const seed=JSON.parse(await readFile(path.join(projectRoot,'backend/scripts/beta_content_seed.json'),'utf8'));
    const title=alias=>seed.tickets.find(t=>t.alias===alias).title;
    const incidentTitle=seed.incidents[0].title;
    const report=await artifactFile('beta-8b6-screens-report.json');
    const prior=process.argv[4]==='--resume'?JSON.parse(await readFile(report,'utf8')):{cases:[],captures:[],requests:[]};
    assert.equal(prior.exceptions?.length??0,0,'Cannot resume a report with exceptions');
    const captures=[...prior.captures],cases=[...prior.cases];
    const saveReport=async(complete)=>writeFile(report,JSON.stringify({date:new Date().toISOString(),complete,cases,captures,requests:[...prior.requests,...requests],exceptions,contentWrites:0},null,2));
    const dismiss=async()=>{for(const type of ['keyDown','keyUp'])await command('Input.dispatchKeyEvent',{type,key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await delay(500);};
    const wheel=async(delta)=>{await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:(await evaluate('innerHeight'))/2,deltaX:0,deltaY:delta});await delay(450);};
    const seek=async(text)=>{for(let i=0;i<25;i++){const s=await state(),height=await evaluate('innerHeight');if(s.controls.some(e=>`${e.text??''} ${e.label??''}`.includes(text)&&e.rect.y>=0&&e.rect.bottom<=height))return;await wheel(400);}throw Error(`Scroll target missing: ${text}`);};
    const openCard=async(text,manager=false)=>{
      for(let i=0;i<30;i++){
        const s=await state(),height=s.viewport.height;
        const items=s.controls.filter(e=>e.role==='button'&&`${e.text??''} ${e.label??''}`.includes(text)&&e.rect.y>=0&&e.rect.bottom<=height);
        items.sort((a,b)=>a.rect.width*a.rect.height-b.rect.width*b.rect.height);
        if(items.length){await click(items[0].rect);return;}
        await wheel(250);
      }
      throw Error(`Visible card missing: ${text}`);
    };
    const shot=async(name)=>{await command('Input.dispatchMouseEvent',{type:'mouseMoved',x:0,y:0});await delay(500);captures.push(path.basename(await capture(`8b6-${name}`)));};
    const preferences=async(dark,lang)=>{
      await evaluate(`localStorage.setItem('flutter.dark','${dark}');localStorage.setItem('flutter.lang',${JSON.stringify(JSON.stringify(lang))});`);
      await command('Page.reload');await delay(700);
      for(let i=0;i<100;i++){
        await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
        const s=await state();
        if(s.controls.some(e=>e.role==='button'&&[lang==='es'?'Ingresar':'Sign in',lang==='es'?'Ajustes':'Settings'].includes(e.text??e.label))){await delay(400);return;}
        await delay(200);
      }
      throw Error('Application did not finish restoring after appearance change');
    };
    for(const [width,height] of [[390,844],[1280,900]])for(const [dark,lang] of [[true,'es'],[false,'en']])for(const [role,key] of [['admin','admin'],['leader','u2'],['developer','u3']]){
      if(cases.some(c=>c.width===width&&c.dark===dark&&c.lang===lang&&c.role===role))continue;
      await preferences(true,'es');await logout();await login(key);
      await command('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      await preferences(dark,lang);
      assert.deepEqual((await state()).viewport,{width,height},'Unexpected viewport');
      const en=lang==='en',prefix=`${role}-${width}-${dark?'dark':'light'}-${lang}`;
      const projects=en?'Projects':'Proyectos',incidents=en?'Incidents':'Incidencias',settings=en?'Settings':'Ajustes';
      await wait(en?'Live updates connected':'Tiempo real conectado');await wait('Portal Clientes');
      await shot(`${prefix}-home`);
      await textTap(projects);await wait('Portal Clientes');await shot(`${prefix}-projects`);
      await textTap('Portal Clientes');await wait('Autenticación y seguridad');await shot(`${prefix}-board`);
      if(role!=='developer'){
        const buttons=(await state()).controls.filter(e=>e.role==='button'&&(e.text===(en?'New ticket':'Nuevo ticket')||e.label===(en?'New ticket':'Nuevo ticket'))&&e.rect.y>=0&&e.rect.bottom<height);
        assert(buttons.length,'New ticket panel button');await click(buttons[0].rect);await wait(en?'Ticket title':'Título del ticket');
        await shot(`${prefix}-new-ticket-panel`);await dismiss();
      }
      for(const alias of ['t1','t2','t4']){
        await wheel(-10000);await openCard(title(alias));await wait(en?'DESCRIPTION':'DESCRIPCIÓN');
        await shot(`${prefix}-${alias}-detail`);
        await seek(en?'Identifier · UUID':'Identificador · UUID');await shot(`${prefix}-${alias}-activity-actions`);
        if(alias==='t1'){
          const label=role==='developer'?(en?'Complete':'Completar'):(en?'Reassign':'Reasignar');
          await tap(label);await wait(role==='developer'?(en?'The Pull Request link is optional':'El enlace de Pull Request es opcional'):'Backend · Líder equipo Pagos');
          await shot(`${prefix}-${role==='developer'?'complete':'assign'}-panel`);await dismiss();
          if(role==='developer'){
            await tap(en?'Raise question':'Plantear pregunta');await wait(en?'Send':'Enviar');await shot(`${prefix}-question-panel`);await dismiss();
          }
          await tap(en?'Redirect':'Redirigir');await wait('Full-stack · Integraciones');await shot(`${prefix}-redirect-panel`);await dismiss();
        }
        if(alias==='t2'&&role!=='developer'){
          await tap(en?'Resume work':'Reanudar trabajo');await wait(en?'Describe how':'Describe cómo');await shot(`${prefix}-resolve-panel`);await dismiss();
        }
        await tap('Back');await wait('Autenticación y seguridad');await delay(500);
      }
      await tap('Back');await wait(projects);await delay(500);
      await textTap('API Pagos');await wait('Conciliación bancaria');await openCard(title('t7'),role!=='developer');await wait(en?'DESCRIPTION':'DESCRIPCIÓN');
      assert((await state()).text.includes(title('t7')),'Unexpected ticket opened from second epic');
      await seek(en?'Identifier · UUID':'Identificador · UUID');await shot(`${prefix}-t7-redirection-history`);
      await tap('Back');await delay(500);await tap('Back');await delay(500);
      await textTap(incidents);await wheel(-10000);await wait(incidentTitle);await shot(`${prefix}-incidents`);
      let incidentCard;
      for(let i=0;i<25&&!incidentCard;i++){
        incidentCard=(await state()).controls.find(e=>e.role==='button'&&`${e.text??''} ${e.label??''}`.includes(incidentTitle)&&e.rect.y>=0&&e.rect.bottom<=height);
        if(!incidentCard)await wheel(300);
      }
      assert(incidentCard,'Visible beta incident card');await click(incidentCard.rect);await wait(en?'Reported by':'Reportada por');await shot(`${prefix}-incident-detail`);
      await seek(en?'Identifier · UUID':'Identificador · UUID');await shot(`${prefix}-incident-actions`);
      if(role!=='developer'){await tap(en?'Assign':'Asignar');await wait('Backend · Líder equipo Pagos');await shot(`${prefix}-incident-assign-panel`);await dismiss();}
      await tap('Back');await delay(500);
      if(role!=='developer'){await textTap(en?'Team':'Equipo');await wait('Backend · Líder equipo Pagos');await shot(`${prefix}-team`);}
      const notifications=(await state()).controls.find(e=>e.role==='button'&&(e.text??e.label??'').startsWith(en?'Notifications':'Notificaciones'));
      assert(notifications,'Notifications button');await click(notifications.rect);await wait(en?'Notifications':'Notificaciones');await shot(`${prefix}-notifications`);await tap('Back');await delay(500);
      await tap(settings);await wait(data.users[key].email);await shot(`${prefix}-settings`);await dismiss();
      cases.push({role,width,height,dark,lang,ticket_details:['t1','t2','t4','t7'],panels:role==='developer'?['complete','question','redirect']:['new','assign','resolve','redirect','incident-assign']});
      assert(!requests.some(r=>['PUT','PATCH','DELETE'].includes(r.method)||r.method==='POST'&&!['/api/auth/login','/api/auth/logout','/api/auth/refresh','/api/auth/ws-ticket'].includes(r.path)),'Screen checks must not mutate content');
      assert.equal(exceptions.length,0,'Runtime exceptions');await saveReport(false);
      console.log(JSON.stringify({case:prefix,captures:captures.filter(n=>n.includes(prefix)).length,exceptions:exceptions.length}));
    }
    await preferences(true,'es');await logout();
    assert(!requests.some(r=>['PUT','PATCH','DELETE'].includes(r.method)||r.method==='POST'&&!['/api/auth/login','/api/auth/logout','/api/auth/refresh','/api/auth/ws-ticket'].includes(r.path)),'Screen checks must not mutate content');
    assert.equal(exceptions.length,0,'Runtime exceptions');
    assert.equal(cases.length,12,'Expected all screen cases');await saveReport(true);
    console.log(JSON.stringify({cases:cases.length,captures:captures.length,contentWrites:0,report}));
  }
  if(action==='reconnect'){
    await command('Page.addScriptToEvaluateOnNewDocument',{source:`window.__betaSockets=[];const Original=window.WebSocket;window.WebSocket=class extends Original{constructor(...args){super(...args);window.__betaSockets.push(this);}};`});
    await command('Page.reload');await delay(2000);await wait('Tiempo real conectado');await delay(1000);await evaluate(`window.__betaSockets.forEach(s=>s.close(3001,'acceptance reconnect'))`);
    for(let i=0;i<100&&frames.filter(f=>f.type==='connected').length<2;i++)await delay(200);
    assert(frames.filter(f=>f.type==='connected').length>=2,'Reconnected handshake');await wait('Tiempo real conectado');await delay(1000);await capture('reconnected');assert(requests.filter(r=>r.path==='/api/auth/ws-ticket'&&r.status===200).length>=2);
  }
  if(action==='event'||action==='support-event'){
    const data=await fixture();
    const relative=path.relative(path.join(projectRoot,'backend'),fixtureFile);
    assert(relative && !relative.startsWith('..') && !path.isAbsolute(relative), 'The event manifest must be inside backend/.');
    const result=await promisify(execFile)('wsl',['-d','Ubuntu-24.04','-u','root','--cd',projectRoot,'--exec','/usr/bin/docker','compose','exec','-T','backend','python','-m',action==='event'?'scripts.acceptance_stage8':'scripts.acceptance_beta',action,data.run_id,'--local-file',`/app/${relative.split(path.sep).join('/')}`]);
    const event=JSON.parse(result.stdout);assert(event.published);await wait(action==='event'?'Evento WS real':'Notificación de soporte');await capture(action==='event'?'live-notification':'support-notification');console.log(JSON.stringify({event}));
  }
  if(action==='notifications'){const button=(await state()).controls.find(e=>e.role==='button'&&e.text.startsWith('Notificaciones'));assert(button);await tap(button.text);await delay(600);}
  if(action==='filters'){if(!(await state()).controls.some(e=>e.role==='tab'))await tap('Back');await textTap('Incidencias');await wait('Todos');const chip=(await state()).controls.find(e=>e.role==='checkbox'&&e.label==='Mitigada');assert(chip);await click(chip.rect);await delay(600);const s=await state();assert(s.text.includes('Incidencias')&&s.text.includes('Incidente mitigated')&&!s.text.includes('Incidente investigating'));await capture('filtered-mitigated');const all=(await state()).controls.find(e=>e.role==='checkbox'&&e.label==='Todos');assert(all);await click(all.rect);}
  if(action==='offline'){await command('Network.emulateNetworkConditions',{offline:true,latency:0,downloadThroughput:0,uploadThroughput:0});await tap('Actualizar');await wait('No se pudo conectar');}
  if(action==='online'){await command('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});await tap('Reintentar');await wait('Tiempo real conectado');await delay(1000);assert(!(await state()).text.includes('No se pudo conectar'));}
  if(action==='network-suite'){
    try{await command('Network.emulateNetworkConditions',{offline:true,latency:0,downloadThroughput:0,uploadThroughput:0});await tap('Actualizar');await wait('No se pudo conectar');await capture('network-error');
      await command('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});await tap('Reintentar');await delay(1500);assert(!(await state()).text.includes('No se pudo conectar'));await capture('network-recovered');
    }finally{await command('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});}
  }
  if(action==='tap')await tap(process.argv[4]);
  if(action==='project')await project();
  if(action==='text')await textTap(process.argv[4]);
  if(action==='fill')await fill(process.argv[4],process.argv[5]);
  if(action==='back'){await command('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await command('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});}
  if(action==='reload'){await command('Page.reload');await delay(1500);await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);}
  if(action==='size'){await command('Emulation.setDeviceMetricsOverride',{width:Number(process.argv[4]),height:Number(process.argv[5]),deviceScaleFactor:1,mobile:false});await delay(500);}
  if(action==='scroll'){await command('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:350,deltaX:0,deltaY:Number(process.argv[4]??400)});await delay(500);}
  await delay(600);
  const screenshot=action==='screenshot'?await capture(process.argv[4]):undefined;
  const current=await state();
   if(!process.argv.includes('--report'))console.log(JSON.stringify({action,screenshot,viewport:current.viewport,text:current.text,controls:current.controls.filter(e=>['button','tab','checkbox','combobox'].includes(e.role)||['INPUT','TEXTAREA'].includes(e.tag)).map(e=>({role:e.role,label:e.label,text:e.text})),requests,creations,frames,baselineExceptions,exceptions},null,2));
   if(action!=='state')assert.equal(exceptions.length,0,'Runtime exceptions');
   if(process.argv.includes('--report')){
     const report=await artifactFile(`8b7-${action}-report.json`);
     await writeFile(report,JSON.stringify({date:new Date().toISOString(),action,requests,creations,frames,exceptions},null,2));
     console.log(JSON.stringify({action,report,requests:requests.length,mutations:requests.filter(r=>r.method!=='GET'&&!r.path.startsWith('/api/auth/')),exceptions:exceptions.length}));
   }
  }
}finally{socket.close();}
