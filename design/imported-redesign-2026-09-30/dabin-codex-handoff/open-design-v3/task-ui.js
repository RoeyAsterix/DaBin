/* Task surfaces. Capture identity/receipt stays intact; focus is independent of reminders. */
Object.assign(icons,{
  taskbox:'M9 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9 M2 4l3 3 5-5 M8 13h8 M8 17h5',
  flag:'M5 21V3 M5 4c5-4 8 4 14 0v10c-6 4-9-4-14 0',
  reset:'M4 8V3 M4 8h5 M4 8a9 9 0 1 1-1 8',
  stop:'M6 6h12v12H6z'
});
const taskFields=['task','planned','scheduledTime','priority','effort','repeat','deadline','checklist','attachments','focus','completed','completedAt'];
let convertedSnapshot=null,taskEditor=null;
function iconAction(icon,label,action,id='',extra=''){
  return `<button type="button" class="icon-btn" data-action="${action}" data-id="${esc(id)}" aria-label="${esc(label)}" title="${esc(label)}" ${extra}>${ic(icon)}</button>`;
}
function durationLabel(minutes){const n=Math.max(0,Math.round(Number(minutes)||0));return n>=60?Math.floor(n/60)+'h'+(n%60?' '+n%60+'m':''):n+'m'}
function focusRemaining(x,now=Date.now()){
  if(x.focus?.endAt)return Math.max(0,Math.ceil((x.focus.endAt-now)/1000));
  return Math.max(0,Number(x.focus?.remaining??(Number(x.effort)||0)*60));
}
function focusClock(x){const seconds=focusRemaining(x);return [Math.floor(seconds/3600),Math.floor(seconds/60)%60,seconds%60].map(n=>String(n).padStart(2,'0')).join(':')}
function focusStatus(x){return x.completed?'Completed':x.focus?.endAt?(focusRemaining(x)?'Focusing':'Time’s up'):x.focus?.remaining===0?'Time’s up':x.focus?'Paused':'Ready when you are'}
function pauseFocus(x){if(x.focus?.endAt)x.focus={remaining:focusRemaining(x)}}
function planLabel(x){return !x.planned?'Schedule':(x.planned===TODAY?'Today':x.planned===dayAdd(TODAY,1)?'Tomorrow':dayLabel(x.planned))+(x.scheduledTime?' · '+x.scheduledTime:'')}
function durationFields(minutes=0){const n=Number(minutes)||0;return `<div class="duration-fields"><label><input name="hours" aria-label="Timer hours" type="number" inputmode="numeric" min="0" max="168" step="1" value="${Math.floor(n/60)}"><span>hours</span></label><span class="duration-colon" aria-hidden="true">:</span><label><input name="minutes" aria-label="Timer minutes" type="number" inputmode="numeric" min="0" max="59" step="1" value="${n%60}"><span>minutes</span></label></div>`}
function durationPresets(){return `<div class="duration-presets" role="group" aria-label="Quick duration">${[15,30,45,60].map(n=>`<button type="button" data-action="duration-preset" data-value="${n}">${durationLabel(n)}</button>`).join('')}</div>`}
function taskCard(x){
  const running=!!x.focus?.endAt&&!x.completed,finished=x.focus?.remaining===0,steps=x.checklist||[];
  return `<article class="task-card ${x.completed?'is-done':''}" data-task-id="${esc(x.id)}" data-capture="${esc(x.id)}" data-od-id="task-${esc(x.id)}">
    <div class="task-card-heading">
      <button type="button" class="task-check" data-action="complete" data-id="${esc(x.id)}" aria-label="${x.completed?'Reopen':'Complete'} ${esc(x.title)}" aria-pressed="${!!x.completed}"><span>${x.completed?ic('check'):''}</span></button>
      <a class="task-card-title" href="${taskRoute(x)}"><span class="task-kicker">${x.completed?'Completed':'Task'}${x.priority==='High'?' · High priority':''}</span><h3>${esc(x.title)}</h3></a>
      ${iconAction('more','More options for '+x.title,'task-menu',x.id)}
    </div>
    ${contentTrail(x,'task')}
    <div class="task-card-context">${x.project?'<span>'+ic('folder')+esc(x.project)+'</span>':''}${steps.length?'<span>'+ic('taskbox')+steps.filter(s=>s.done).length+'/'+steps.length+'</span>':''}${x.deadline?'<span>'+ic('flag')+'Due '+dayLabel(x.deadline.slice(0,10))+'</span>':''}${x.attachments?.length?'<span>'+ic('clip')+x.attachments.length+'</span>':''}</div>
    <div class="task-card-controls">
      <div class="task-focus-control" data-running="${running}"><button type="button" class="task-duration" data-action="task-duration" data-id="${esc(x.id)}" aria-label="Set timer for ${esc(x.title)}">${ic('clock')}<span data-timer-clock="${esc(x.id)}">${x.focus?focusClock(x):x.effort?String(Math.floor(x.effort/60)).padStart(2,'0')+'h '+String(x.effort%60).padStart(2,'0')+'m':'Set timer'}</span></button>${!x.completed?`<button type="button" class="focus-play" data-action="timer-toggle" data-id="${esc(x.id)}" data-timer-button="${esc(x.id)}" aria-label="${running?'Pause':finished?'Restart':'Start'} timer for ${esc(x.title)}" title="${running?'Pause':'Start'} timer">${ic(running?'pause':'play')}</button>`:''}</div>
      <button type="button" class="task-schedule" data-action="task-schedule" data-id="${esc(x.id)}" aria-label="Schedule ${esc(x.title)}">${ic('calendar')}<span>${esc(planLabel(x))}</span></button>
    </div>
    <span class="sr-only" data-timer-status="${esc(x.id)}">${focusStatus(x)}</span>
  </article>`;
}
function taskDetailView(x){
  const draft=state.drafts[x.id],v=draft?{...x,...draft}:x,steps=v.checklist||[];
  return `<div class="task-detail-top"><button class="back" data-action="back">${ic('back')} Back</button><div class="row">${iconAction('pin',x.pinned?'Unpin task':'Pin task','pin',x.id)}<a class="icon-btn" href="reminder.html?id=${esc(x.id)}" aria-label="${x.reminder?'Edit':'Add'} reminder" title="${x.reminder?'Edit':'Add'} reminder">${ic('bell')}</a>${iconAction('more','More task actions','card-menu',x.id)}</div></div>
  <form id="detail-form" class="task-editor" data-od-id="task-editor">
    <div class="task-heading"><button type="button" class="task-check" data-action="complete" data-id="${esc(x.id)}" aria-label="${x.completed?'Reopen':'Complete'} ${esc(x.title)}" aria-pressed="${!!x.completed}"><span>${x.completed?ic('check'):''}</span></button><div class="grow"><span class="task-kicker">${x.completed?'Completed':'Task'}</span><label class="sr-only" for="task-title">Task title</label><textarea class="task-title-input" id="task-title" name="title" rows="2" required maxlength="500">${esc(v.title)}</textarea></div></div>
    <div class="task-property-row"><button type="button" class="property-chip" data-action="task-project" data-id="${esc(x.id)}">${ic('folder')}${esc(v.project||'Add project')}</button><input type="hidden" name="project" value="${esc(v.project||'')}"><input type="checkbox" name="pinned" ${x.pinned?'checked':''} hidden><div class="priority-control" role="group" aria-label="Priority">${['None','Low','Medium','High'].map((p,i)=>`<button type="button" data-action="task-priority" data-value="${p}" aria-pressed="${(v.priority||'None')===p}" aria-label="${p==='None'?'No priority':p+' priority'}" title="${p==='None'?'No priority':p+' priority'}">${i?'<span class="priority-bars" aria-hidden="true">'+Array.from({length:3},(_,j)=>'<i class="'+(j<i?'filled':'')+'"></i>').join('')+'</span>':ic('flag')}</button>`).join('')}</div><input type="hidden" name="priority" value="${esc(v.priority||'None')}"></div>
    ${contentTrail(x,'detail')}
    <div class="task-planning-grid">
      <section class="focus-panel"><div class="row between"><h2>${ic('clock')} Focus timer</h2>${iconAction('reset','Reset timer','timer-reset',x.id)}</div><output class="focus-digits" data-timer-clock="${esc(x.id)}">${focusClock(x)}</output><div class="timer-units">HOURS <span>MINUTES</span> SECONDS</div><div class="focus-panel-footer"><button type="button" class="text-control" data-action="task-duration" data-id="${esc(x.id)}">${x.effort?durationLabel(x.effort)+' session':'Set duration'}</button><button type="button" class="btn primary" data-action="timer-toggle" data-id="${esc(x.id)}" data-timer-button="${esc(x.id)}" data-expanded="true" ${x.completed?'disabled':''}>${ic(x.focus?.endAt?'pause':'play')} ${x.focus?.endAt?'Pause':'Start'}</button></div><span class="timer-status" data-timer-status="${esc(x.id)}">${focusStatus(x)}</span></section>
      <section class="schedule-panel"><h2>${ic('calendar')} Schedule</h2><button type="button" class="schedule-date" data-action="task-schedule" data-id="${esc(x.id)}"><strong>${!v.planned?'Pick a day':v.planned===TODAY?'Today':v.planned===dayAdd(TODAY,1)?'Tomorrow':dayLabel(v.planned)}</strong><span>${v.planned?fullDay(v.planned):'When do you want to work?'}</span>${v.scheduledTime?'<b>'+esc(v.scheduledTime)+'</b>':''}</button><div class="quick-days"><button type="button" data-action="task-quick-day" data-id="${esc(x.id)}" data-value="${TODAY}">Today</button><button type="button" data-action="task-quick-day" data-id="${esc(x.id)}" data-value="${dayAdd(TODAY,1)}">Tomorrow</button>${iconAction('calendar','Choose date and time','task-schedule',x.id)}</div></section>
    </div>
    <input type="hidden" name="planned" value="${esc(v.planned||'')}"><input type="hidden" name="scheduledTime" value="${esc(v.scheduledTime||'')}"><input type="hidden" name="effort" value="${v.effort||''}">
    <section class="task-steps"><div class="row between"><h2>Steps</h2><span class="meta">${steps.filter(s=>s.done).length}/${steps.length}</span></div><div class="checklist">${steps.map((s,i)=>`<label><input type="checkbox" data-check="${i}" ${s.done?'checked':''}><input type="text" data-step="${i}" maxlength="500" value="${esc(s.text)}" aria-label="Checklist step ${i+1}">${iconAction('x','Remove checklist step '+(i+1),'remove-step','',`data-value="${i}"`)}</label>`).join('')}</div><button type="button" class="text-control" data-action="add-step">${ic('plus')} Add a step</button></section>
    <details class="task-fold" ${draft?.comment?'open':''}><summary>${ic('note')} Notes ${v.comment?'<span class="count">1</span>':''}${ic('plus')}</summary><textarea name="comment" rows="3" placeholder="Add context…">${esc(v.comment||'')}</textarea></details>
    <details class="task-fold"><summary>${ic('clip')} Original capture & attachments <span class="count">${(x.attachments||[]).length}</span>${ic('plus')}</summary><div class="task-original">${x.image?'<img src="'+esc(x.image)+'" alt="'+esc(x.title)+'">':''}<p dir="auto">${esc(x.text||'Saved file')}</p><span class="meta">${esc(x.source||'DaBin')} · ${dayLabel(x.date)} · ${x.time}</span><div class="actions-inline">${button(ic('copy')+' Copy','copy','',x.id)}${x.url?'<a class="btn" href="'+safeURL(x.url)+'" target="_blank" rel="noopener">'+ic('external')+' Open</a>':''}${button(ic('folder')+' File location','file-location','',x.id)}${x.indexed?button('Recognized text','index-status','',x.id):''}</div></div>${x.indexed?'<div class="task-original"><h3>Recognized text</h3><p>'+esc(x.indexed)+'</p>'+button('Copy text','copy-index','',x.id)+'</div>':''}<div class="attachment-list">${[...new Set([...(x.attachments||[]),...(x.members||[])])].map(id=>item(id)).filter(Boolean).map(f=>'<a href="capture-detail.html?id='+esc(f.id)+'">'+ic(f.type==='Media'?'image':'file')+esc(f.title)+'</a>').join('')}</div><div class="actions-inline">${button(ic('plus')+' Saved item','attach-existing','',x.id)}${button(ic('clip')+' Import','attach-import','',x.id)}${button(ic('copy')+' Paste','attach-paste','',x.id)}</div></details>
    <details class="task-fold"><summary>${ic('refresh')} Repeat & deadline${ic('plus')}</summary><label class="field">Repeat</label><div class="repeat-options" role="group" aria-label="Repeat">${['None','Daily','Weekdays','Weekly','Monthly'].map(p=>`<button type="button" data-action="task-repeat" data-value="${p}" aria-pressed="${(v.repeat||'None')===p}">${p}</button>`).join('')}</div><input type="hidden" name="repeat" value="${esc(v.repeat||'None')}"><label class="field">Finish by<input type="datetime-local" name="deadline" value="${esc(v.deadline||'')}"></label></details>
    ${x.previous?'<a class="small-link" href="task-detail.html?id='+esc(x.previous)+'">Previous occurrence</a>':''}${x.next?'<a class="small-link" href="task-detail.html?id='+esc(x.next)+'">Next occurrence</a>':''}
    <div class="task-savebar"><span class="meta" id="task-save-state">${draft?'Unsaved changes':'Saved'}</span><button class="btn primary" type="submit">Save changes</button></div>
  </form>`;
}
function openTaskDuration(id,startAfter=false){const x=item(id);taskEditor={id,kind:'duration',startAfter};openDialog('Focus timer',`<form id="task-duration-form" class="timing-form"><p class="timing-task-name">${esc(x.title)}</p>${durationFields(x.effort)}${durationPresets()}<div class="actions"><button type="button" class="btn" data-action="close-dialog">Cancel</button><button class="btn primary" type="submit">${startAfter?'Start timer':'Set timer'}</button></div></form>`)}
function openTaskSchedule(id){const x=item(id),v={...x,...state.drafts[id]};taskEditor={id,kind:'schedule'};openDialog('Schedule task',`<form id="task-schedule-form" class="timing-form"><p class="timing-task-name">${esc(x.title)}</p><div class="quick-days"><button type="button" data-action="schedule-preset" data-value="${TODAY}">Today</button><button type="button" data-action="schedule-preset" data-value="${dayAdd(TODAY,1)}">Tomorrow</button></div><div class="schedule-fields"><label class="field">Day<input type="date" name="planned" required value="${v.planned||TODAY}"></label><label class="field">Time <span class="optional">Optional</span><input type="time" name="scheduledTime" value="${esc(v.scheduledTime||'')}"></label></div><div class="actions">${v.planned?button('Clear','task-clear-schedule','',id):button('Cancel','close-dialog')}<button class="btn primary" type="submit">Schedule</button></div></form>`)}
function updateTaskPlan(id,patch){return change(()=>{Object.assign(item(id),patch);if(state.drafts[id])Object.assign(state.drafts[id],patch)},false)}
function refreshTaskUI(id){const modal=$('#dialog');if(modal?.open)closeDialog();render();const card=$$('[data-task-id]').find(n=>n.dataset.taskId===id);card?.classList.add('task-arrived');card?.querySelector('.task-duration')?.focus({preventScroll:true})}
function convertCapture(id){const x=item(id);if(!x||x.task){if(x)go('task-detail','?id='+encodeURIComponent(id));return}const snapshot=Object.fromEntries(taskFields.map(k=>[k,x[k]]));if(!change(()=>{x.task=true;x.checklist??=[];x.attachments??=[]},false))return;convertedSnapshot={id,snapshot};if(PAGE==='capture-detail'){go('task-detail','?id='+encodeURIComponent(id));return}refreshTaskUI(id);toast('Task created',false,'<button data-action="undo-task-conversion">Undo</button>')}
function toggleFocus(id){const x=item(id);if(!x||x.completed)return;if(!x.effort){openTaskDuration(id,true);return}if(!change(()=>{if(x.focus?.endAt)pauseFocus(x);else{x.focus={remaining:focusRemaining(x)||x.effort*60,endAt:Date.now()+(focusRemaining(x)||x.effort*60)*1000}}},false))return;updateTaskTimers()}
function updateTaskTimers(){
  const ended=alive().filter(x=>x.focus?.endAt&&x.focus.endAt<=Date.now());
  if(ended.length&&change(()=>ended.forEach(x=>x.focus={remaining:0}),false))toast(ended.length===1?'Timer finished · '+ended[0].title:'Focus timers finished');
  $$('[data-timer-clock]').forEach(n=>{const x=item(n.dataset.timerClock);if(!x)return;n.textContent=n.closest('.focus-panel')||x.focus?focusClock(x):x.effort?String(Math.floor(x.effort/60)).padStart(2,'0')+'h '+String(x.effort%60).padStart(2,'0')+'m':'Set timer'});
  $$('[data-timer-button]').forEach(n=>{const x=item(n.dataset.timerButton);if(!x)return;const running=!!x.focus?.endAt&&!x.completed,label=running?'Pause':x.focus?.remaining===0?'Restart':'Start';n.setAttribute('aria-label',label+' timer for '+x.title);n.title=label+' timer';n.innerHTML=ic(running?'pause':'play')+(n.dataset.expanded?' '+label:'');n.disabled=!!x.completed;n.closest('.task-focus-control')?.setAttribute('data-running',String(running))});
  $$('[data-timer-status]').forEach(n=>{const x=item(n.dataset.timerStatus);if(x)n.textContent=focusStatus(x)});
}
function chooseTaskProject(id){const x={...item(id),...state.drafts[id]};openDialog('Project',`<div class="project-options">${['',...state.projects].map(p=>`<button type="button" data-action="task-project-select" data-id="${esc(id)}" data-value="${esc(p)}" aria-pressed="${(x.project||'')===p}">${ic('folder')}<span>${esc(p||'Unfiled')}</span>${(x.project||'')===p?ic('check'):''}</button>`).join('')}</div>`)}
async function handleTaskAction(a){const act=a.dataset.action,id=a.dataset.id||currentId,val=a.dataset.value;
  switch(act){
    case 'project-picker':openProjectSwitcher(a);return true;
    case 'project-pick':if(change(()=>state.project=val,false)){closeDialog();render()}return true;
    case 'project-new':closeDialog();askName('New project','','new-project-save');return true;
    case 'task-duration':openTaskDuration(id);return true;
    case 'task-schedule':openTaskSchedule(id);return true;
    case 'timer-toggle':toggleFocus(id);return true;
    case 'timer-reset':if(change(()=>{delete item(id).focus},false))updateTaskTimers();return true;
    case 'duration-preset':{const f=a.closest('form');f.elements.hours.value=Math.floor(Number(val)/60);f.elements.minutes.value=Number(val)%60;f.dispatchEvent(new Event('input',{bubbles:true}));return true}
    case 'schedule-preset':a.closest('form').elements.planned.value=val;return true;
    case 'task-quick-day':case 'task-clear-schedule':{if(updateTaskPlan(id,{planned:act==='task-clear-schedule'?null:val,scheduledTime:act==='task-clear-schedule'?null:item(id).scheduledTime})){refreshTaskUI(id);toast(act==='task-clear-schedule'?'Schedule cleared':'Scheduled')}return true}
    case 'task-project':chooseTaskProject(id);return true;
    case 'task-project-select':if(updateTaskPlan(id,{project:val||null})){refreshTaskUI(id);toast('Project saved')}return true;
    case 'task-priority':case 'task-repeat':{const f=$('#detail-form'),field=act==='task-priority'?'priority':'repeat';f.elements[field].value=val;a.parentElement.querySelectorAll('button').forEach(n=>n.setAttribute('aria-pressed',String(n===a)));detailDraft();return true}
    case 'undo-task-conversion':{if(!convertedSnapshot)return true;const {id:convertedId,snapshot}=convertedSnapshot;if(change(()=>{const x=item(convertedId);taskFields.forEach(k=>{if(snapshot[k]===undefined)delete x[k];else x[k]=snapshot[k]})})){convertedSnapshot=null;toast('Capture restored')}return true}
  }
  return false;
}
function submitTaskTiming(e){const f=e.target;if(!['task-duration-form','task-schedule-form'].includes(f.id))return;e.preventDefault();const id=taskEditor.id;
  if(f.id==='task-duration-form'){
    const h=Number(f.elements.hours.value),m=Number(f.elements.minutes.value),total=h*60+m;
    if(!Number.isInteger(h)||!Number.isInteger(m)||h<0||m<0||m>59||total<=0||total>10080){toast('Choose 1 minute to 168 hours.',true);return}
    const startAfter=taskEditor.startAfter,patch={effort:total,focus:startAfter?{remaining:total*60,endAt:Date.now()+total*60000}:undefined};
    if(updateTaskPlan(id,patch)){refreshTaskUI(id);toast(startAfter?'Timer started':'Timer set')}
  }else if(f.elements.planned.value){if(updateTaskPlan(id,{planned:f.elements.planned.value,scheduledTime:f.elements.scheduledTime.value||null})){refreshTaskUI(id);toast('Task scheduled')}}
}
