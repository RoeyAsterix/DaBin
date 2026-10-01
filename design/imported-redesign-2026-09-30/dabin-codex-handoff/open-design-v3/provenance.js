/* Content provenance: local app marks, preserved origin, explicit paste receipts.
   Copying is not a paste receipt. Browser destinations are always user-recorded. */
icons.app='M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 8h8v8H8z';
const trailApps = [
  {id:'mail',name:'Mail',bundle:'com.apple.mail'},
  {id:'notes',name:'Notes',bundle:'com.apple.Notes'},
  {id:'finder',name:'Finder',bundle:'com.apple.finder'},
  {id:'safari',name:'Safari',bundle:'com.apple.Safari'},
  {id:'chrome',name:'Chrome',bundle:'com.google.Chrome'},
  {id:'slack',name:'Slack',bundle:'com.tinyspeck.slackmacgap'},
  {id:'dabin',name:'DaBin'}
];
function trailIdentity(value,label='') {
  const v=String(value||'').trim(),key=v.toLowerCase()==='google chrome'?'chrome':v.toLowerCase();
  const found=trailApps.find(a=>[a.id,a.name,a.bundle||''].some(s=>s.toLowerCase()===key&&key));
  return found||{id:'unknown',name:String(label||v||'Unknown source').slice(0,100)};
}
function captureOrigin(x) {
  // A product identity is accepted only when supplied by the capture adapter.
  return trailIdentity(x.sourceProduct||x.sourceApplicationBundleIdentifier||x.sourceApplicationName||x.source);
}
function appMark(app) {
  const src=app.id==='dabin'?ASSETS+'original-robot.svg':trailApps.some(a=>a.id===app.id)?ASSETS+'app-icons/'+app.id+'.png':null;
  return `<span class="app-mark${src?'':' app-mark-unknown'}" aria-hidden="true">${src?'<img src="'+src+'" alt="" width="28" height="28" loading="lazy">':ic('app')}</span>`;
}
function pasteReceipts(x) {
  return (Array.isArray(x.pasteHistory)?x.pasteHistory:[]).filter(p=>p&&['manual','confirmed'].includes(p.kind)&&typeof p.app==='string'&&p.app.trim()).slice().sort((a,b)=>(Date.parse(b.at)||0)-(Date.parse(a.at)||0));
}
function pasteDestinations(x) {
  const destinations=[];
  for(const p of pasteReceipts(x)) {
    const app=trailIdentity(p.app,p.label),key=app.id==='unknown'?app.name.toLowerCase():app.id;
    const found=destinations.find(d=>d.key===key);
    if(found)found.count++;else destinations.push({key,app,count:1});
  }
  return destinations;
}
function trailSummary(x) {
  const from=captureOrigin(x).name,dest=pasteDestinations(x);
  return 'From '+from+'. '+(dest.length?'Pasted to '+dest.map(d=>d.app.name+(d.count>1?' ('+d.count+' times)':'')).join(', ')+'.':'No paste destinations recorded.')+' Open content trail.';
}
function contentTrail(x,mode='card') {
  const from=captureOrigin(x),dest=pasteDestinations(x),summary=trailSummary(x);
  return `<div class="content-trail trail-${mode}" data-od-id="trail-${esc(x.id)}">
    <button type="button" class="trail-path" data-action="content-trail" data-id="${esc(x.id)}" aria-label="${esc(summary)}" title="${esc(summary)}">
      ${appMark(from)}<span class="trail-direction">${ic('arrow')}</span>
      <span class="trail-destinations">${dest.length?dest.slice(0,3).map(d=>appMark(d.app)).join('')+(dest.length>3?'<span class="trail-overflow">+'+(dest.length-3)+'</span>':''):'<span class="trail-empty">No pastes</span>'}</span>
    </button>
    <button type="button" class="trail-add" data-action="paste-picker" data-id="${esc(x.id)}" aria-label="Record a paste destination for ${esc(x.title)}" title="Record a paste destination">${ic('plus')}</button>
  </div>`;
}
function receiptTime(at) {
  const d=new Date(at);
  return Number.isFinite(d.getTime())?d.toLocaleString('en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}):'Time unavailable';
}
function trailDialog(x,picker=false) {
  const origin=captureOrigin(x),history=pasteReceipts(x);
  const body=`<div class="trail-origin"><span class="trail-caption">FROM</span>${appMark(origin)}<div><strong>${esc(origin.name)}</strong><span>${esc(dayLabel(x.date))} · ${esc(x.time||'')}</span></div></div>
    <div class="trail-history-head"><h3>Pasted to</h3>${history.length?'<span class="count">'+history.length+'</span>':''}</div>
    <div class="paste-history" role="list">${history.length?history.map(p=>`<div class="paste-receipt" role="listitem">${appMark(trailIdentity(p.app,p.label))}<div class="grow"><strong>${esc(trailIdentity(p.app,p.label).name)}</strong><span>${p.kind==='manual'?'Recorded by you':'Confirmed paste'} · ${esc(receiptTime(p.at))}</span>${p.context?'<small>'+esc(p.context)+'</small>':''}</div>${p.kind==='manual'?'<button type="button" class="icon-btn" data-action="paste-remove" data-id="'+esc(x.id)+'" data-value="'+esc(p.id)+'" aria-label="Remove recorded paste to '+esc(trailIdentity(p.app,p.label).name)+'">'+ic('x')+'</button>':''}</div>`).join(''):'<p class="trail-no-history">No paste destinations recorded.</p>'}</div>
    ${picker?`<form id="paste-record-form" data-capture-id="${esc(x.id)}" class="paste-picker"><h3>Record a paste</h3><p>Choose where you pasted. This adds a record; it doesn’t paste content.</p><div class="paste-app-grid">${trailApps.map(app=>'<button type="button" class="paste-app-choice" data-action="paste-record" data-id="'+esc(x.id)+'" data-value="'+app.id+'">'+appMark(app)+'<span>'+esc(app.name)+'</span></button>').join('')}</div><label class="sr-only" for="paste-app-name">Another app or product</label><div class="paste-custom"><input id="paste-app-name" name="application" placeholder="Another app or product…" required maxlength="100" autocomplete="off"><button type="submit" class="btn">Add</button></div></form>`:'<button type="button" class="trail-record-button" data-action="paste-picker" data-id="'+esc(x.id)+'">'+ic('plus')+' Record a paste</button>'}`;
  openDialog('Content trail',body);
  const form=$('#paste-record-form');
  form?.addEventListener('submit',e=>{e.preventDefault();const name=form.elements.application.value.trim();if(name)commitManualPaste(x.id,name)});
}
function recordManualPaste(id,value) {
  const x=item(id),app=trailIdentity(value);
  if(!x||x.deleted||!String(value||'').trim()||String(value).trim().length>100)return false;
  const receipt={id:'paste-'+(typeof crypto!=='undefined'&&crypto.randomUUID?crypto.randomUUID():Date.now()+'-'+Math.random().toString(36).slice(2)),app:app.id==='unknown'?app.name:app.id,at:new Date().toISOString(),kind:'manual'};
  return change(()=>{if(!Array.isArray(x.pasteHistory))x.pasteHistory=[];x.pasteHistory.push(receipt)},false);
}
function removeManualPaste(id,receiptId) {
  const x=item(id);if(!x||!pasteReceipts(x).some(p=>p.id===receiptId&&p.kind==='manual'))return false;
  return change(()=>{x.pasteHistory=x.pasteHistory.filter(p=>p.id!==receiptId||p.kind!=='manual')},false);
}
function refreshTrailDialog(id) {
  closeDialog();render();
  document.querySelectorAll('[data-action="content-trail"]').forEach(el=>{if(el.dataset.id===id)el.focus()});
  trailDialog(item(id));
}
function commitManualPaste(id,value) {
  if(!recordManualPaste(id,value))return;
  refreshTrailDialog(id);toast('Paste destination recorded');
}
function handleTrailAction(a) {
  const action=a.dataset.action,id=a.dataset.id,x=item(id);
  if(!['content-trail','paste-picker','paste-record','paste-remove'].includes(action))return false;
  if(!x||x.deleted)return true;
  if(action==='content-trail'||action==='paste-picker') {
    if($('#detail-form'))detailDraft();
    trailDialog(x,action==='paste-picker');
  }else if(action==='paste-record')commitManualPaste(id,a.dataset.value);
  else if(removeManualPaste(id,a.dataset.value))refreshTrailDialog(id);
  return true;
}
