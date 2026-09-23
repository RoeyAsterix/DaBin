const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const M=require('../DaBin/open-design-v2/model.js');
const day='2026-09-22',seed=M.seed(day),checks=[];
function check(name,fn){fn();checks.push(name)}
check('Text, HTTP links, and unsafe URI classification',()=>{assert.equal(M.classify('hello'),'text');assert.equal(M.classify('https://example.com/a'),'link');assert.equal(M.classify('javascript:alert(1)'),'text')});
check('File groups and MIME-less extension fallbacks',()=>{for(const [name,kind] of [['x.pdf','pdf'],['x.ai','ai'],['x.pptx','document'],['x.jpg','image'],['x.mp4','video'],['x.bin','file']])assert.equal(M.fileKind({name,type:''}),kind);assert.equal(M.group({kind:'ai'}),'files');assert.equal(M.group({kind:'video'}),'media')});
check('Comment and reminder edits preserve capture identity, time, day and timezone',()=>{const a=seed[0],b=M.edit(a,'Changed','2026-12-31T10:00');for(const key of ['id','day','capturedAt','zone'])assert.equal(b[key],a[key]);assert.equal(b.comment,'Changed')});
check('Single-hit search includes only immediate same-day neighbors',()=>{const g=M.search(seed,'quiet forms');assert.equal(g.length,1);assert.equal(g[0].items.length,2);assert.equal(g[0].items[0].match,true);assert.equal(g[0].items[1].entry.id,'thought')});
check('Multi-day search includes only dates with a match',()=>{const r=M.search(seed,'room');assert.equal(r.length,3);r.forEach(g=>assert(g.items.some(i=>i.match)));assert.equal(M.search(seed,'not-existing').length,0)});
check('Overlapping search context is deduplicated and cannot cross midnight',()=>{const list=[0,1,2,3,4].map(i=>({id:''+i,day,capturedAt:`2026-09-22T0${i}:00:00Z`,kind:'text',title:i===1||i===2?'hit':'context'}));list.push({id:'prior',day:'2026-09-21',capturedAt:'2026-09-21T23:59:00Z',kind:'text',title:'context'});const r=M.search(list,'hit');assert.equal(r.length,1);assert.deepEqual(r[0].items.map(i=>i.entry.id),['0','1','2','3']);assert.equal(r[0].items.filter(i=>i.match).length,2)});
check('Type filter restricts hits but preserves other-type context',()=>{const g=M.search(seed,'room','links');assert.equal(g.length,2);const y=g.find(g=>g.day==='2026-09-21');assert.deepEqual(y.items.map(i=>i.entry.kind),['text','link','document']);assert.equal(y.hits,1)});
check('Local dates roll over month and year boundaries',()=>{assert.equal(M.shift('2026-12-31',1),'2027-01-01');assert.equal(M.shift('2026-03-01',-1),'2026-02-28')});
// DOM-neutral smoke harness: verifies generated screen markup and handlers, not browser layout.
async function smoke(screen,params=''){
 const nodes=new Map(),events={},storage=new Map(),tools=[];
 class El{constructor(){this.innerHTML='';this.value='';this.dataset={};this.style={};this.hidden=false;this.classList={add(){},remove(){}}}focus(){}click(){}setPointerCapture(){}getBoundingClientRect(){return{x:1200,y:400}}matches(){return false}}
 const get=s=>{if(!nodes.has(s))nodes.set(s,new El());return nodes.get(s)};
 const document={body:{dataset:{screen}},documentElement:{dataset:{}},querySelector:get,querySelectorAll:()=>[],createElement:()=>new El(),addEventListener:(name,fn)=>events[name]=fn,modelContext:{registerTool:tool=>tools.push(tool)}};
 const local={getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)};
 const ctx={DaBinModel:M,document,location:{search:params,href:''},localStorage:local,sessionStorage:local,URLSearchParams,URL,Date,Intl,crypto:require('node:crypto').webcrypto,console,history:{replaceState(){}},innerWidth:1440,innerHeight:900,AbortController,navigator:{clipboard:{writeText:async()=>{}}},setTimeout:(f,t)=>{if(t<=480)Promise.resolve().then(f);return 1},clearTimeout(){}};ctx.window=ctx;ctx.addEventListener=()=>{};ctx.open=()=>{};
 vm.createContext(ctx);await vm.runInContext(fs.readFileSync('DaBin/open-design-v2/app.js','utf8'),ctx);
 assert(ctx.DaBinApp,screen+' initialized');assert.equal(tools.length,2);
 if(screen!=='rest')assert(get('#panel').innerHTML.includes(screen==='detail'?'detail-form':screen==='daily'?'captures':screen==='search'?'results':screen==='capture'?'capture-form':'Reminders'));
 if(screen==='capture'){
  const before=ctx.DaBinApp.entries.length;
  await ctx.DaBinApp.saveText('https://example.com/one\nhttps://example.com/two');assert.equal(ctx.DaBinApp.entries.length,before+2);
  const made=ctx.DaBinApp.entries.slice(-2);assert(made.every(e=>e.day===M.dayKey(new Date())));
  await ctx.DaBinApp.saveText('   ');assert.equal(ctx.DaBinApp.entries.length,before+2);assert.equal(get('#widget').dataset.state,'failure');
  const saved=await tools.find(t=>t.name==='save_text_capture').execute({text:'A new thought'});assert.equal(saved.length,1);
  await assert.rejects(()=>tools.find(t=>t.name==='save_text_capture').execute({text:''}));
  assert.throws(()=>tools.find(t=>t.name==='search_captures').execute({query:42}));
 }
 if(screen==='detail'){
  const before=ctx.DaBinApp.entries.find(e=>e.id==='thought');get('#comment').value='A saved comment';get('#reminder').value='2026-12-31T09:30';get('#detail-form').onsubmit({preventDefault(){}});
  const after=ctx.DaBinApp.entries.find(e=>e.id==='thought');assert.equal(after.comment,'A saved comment');assert.equal(after.capturedAt,before.capturedAt);assert.equal(after.day,before.day);
 }
 return screen;
}
(async()=>{for(const s of ['daily','capture','search','detail','reminders','rest']){await smoke(s,s==='detail'?'?id=thought':s==='search'?'?q=room':'');checks.push(s+' initialization and primary handler smoke check')}
 const result={status:'passed',count:checks.length,checks,limits:['DOM-neutral smoke harness is not rendered browser QA.','Native double-click threshold, OS drag delivery, dark appearance, and layout require real browser/native checks.','WebMCP handlers tested in mock registration context; no supported browser WebMCP context was available.']};fs.writeFileSync('DaBin/open-design-v2/review/qa-results.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2))})().catch(e=>{console.error(e);process.exit(1)});
