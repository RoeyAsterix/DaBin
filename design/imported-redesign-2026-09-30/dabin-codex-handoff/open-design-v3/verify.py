"""Local JavaScriptCore checks. These are behavior/markup checks, not browser-layout QA."""
import ctypes as C,json,re
from pathlib import Path
from html.parser import HTMLParser
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'open-design-v3'
j=C.CDLL('/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore')
def bind(n,args,restype):
 f=getattr(j,n);f.argtypes=args;f.restype=restype;return f
create=bind('JSGlobalContextCreate',[C.c_void_p],C.c_void_p)
release=bind('JSGlobalContextRelease',[C.c_void_p],None)
string=bind('JSStringCreateWithUTF8CString',[C.c_char_p],C.c_void_p)
free=bind('JSStringRelease',[C.c_void_p],None)
evaluate=bind('JSEvaluateScript',[C.c_void_p,C.c_void_p,C.c_void_p,C.c_void_p,C.c_int,C.POINTER(C.c_void_p)],C.c_void_p)
to_string=bind('JSValueToStringCopy',[C.c_void_p,C.c_void_p,C.POINTER(C.c_void_p)],C.c_void_p)
size=bind('JSStringGetMaximumUTF8CStringSize',[C.c_void_p],C.c_size_t)
bytes_=bind('JSStringGetUTF8CString',[C.c_void_p,C.c_char_p,C.c_size_t],C.c_size_t)
class JS:
 def __init__(self):self.ctx=create(None)
 def run(self,code):
  s=string(code.encode());err=C.c_void_p();v=evaluate(self.ctx,s,None,None,1,C.byref(err));free(s)
  obj=to_string(self.ctx,err.value or v,None);buf=C.create_string_buffer(size(obj));bytes_(obj,buf,len(buf));free(obj)
  result=buf.value.decode()
  if err.value:raise RuntimeError(result)
  return result
stub="""
var storage={},failSave=false,htmlNodes={};
var localStorage={getItem:k=>storage[k]||null,setItem:(k,v)=>{if(failSave)throw Error('full');storage[k]=v}};
var sessionStorage={getItem:k=>storage[k]||null,setItem:(k,v)=>storage[k]=v};
var location={search:'',href:'http://fixture/inbox.html'};
var URLSearchParams=class{get(k){return null}has(k){return false}};
var fake=()=>({innerHTML:'',value:'',dataset:{},style:{setProperty(k,v){this[k]=v}},classList:{add(){},remove(){},toggle(){}},addEventListener(){},setAttribute(){},removeAttribute(){},querySelector(){return fake()},querySelectorAll(){return []},focus(){},close(){},showModal(){}});
var document={body:{dataset:{page:PAGE_NAME}},documentElement:fake(),querySelector:s=>htmlNodes[s]||(htmlNodes[s]=fake()),querySelectorAll:()=>[]};
var window={};var navigator={};var setTimeout=()=>0,clearTimeout=()=>{};
"""
names=['model.js','provenance.js','views.js','project-picker.js','responsive.js','task-ui.js','settings.js','interactions.js','events.js']
scripts={n:(SRC/n).read_text() for n in names}
results=[]
def check(name,condition,detail=''):
 results.append({'check':name,'passed':bool(condition),'detail':detail})
js=JS()
for n,s in scripts.items():
 try:js.run('new Function('+json.dumps(s)+'); "parsed"');check('Syntax: '+n,True)
 except Exception as e:check('Syntax: '+n,False,str(e))
def context(page='inbox'):
 c=JS();c.run(stub.replace('PAGE_NAME',json.dumps(page)))
 for n in names[:-1]:c.run(scripts[n])
 c.run('render=()=>{};toast=(text)=>{window.lastToast=text};closeDialog=()=>{};')
 return c
pages=json.loads((SRC/'screen-index.json').read_text())['product_screens']
for page in pages:
 try:
  c=context(page);html=c.run('view()');check('Screen markup: '+page,len(html)>100)
  for href in re.findall(r'href="([^"#]+)"',html):
   path=href.split('?')[0]
   if not re.match(r'^(https?:|data:)',path):check('Linked route: '+page+' → '+path,(ROOT/path).exists())
 except Exception as e:check('Screen markup: '+page,False,str(e))
class TaskFormStructure(HTMLParser):
 def __init__(self):
  super().__init__(convert_charrefs=True);self.stack=[];self.errors=[];self.fields=[]
 def handle_starttag(self,t,a):
  a=dict(a)
  if t in ('input','textarea','select') and a.get('name'):self.fields.append((a['name'],'form' in self.stack))
  if t not in ('area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'):self.stack.append(t)
 def handle_endtag(self,t):
  if not self.stack or self.stack[-1]!=t:self.errors.append('Unexpected closing '+t)
  if t in self.stack:
   while self.stack.pop()!=t:pass
for page in ['inbox','today','task-detail','new-task']:
 c=context(page);parser=TaskFormStructure();parser.feed(c.run('view()'))
 check('Balanced task markup: '+page,not parser.errors and not parser.stack,str(parser.errors))
 check('Named fields remain inside form: '+page,all(inside for name,inside in parser.fields))
c=context()
tests={
 'Both monitoring channels start off':"!state.settings.clipboard&&!state.settings.screenshots",
 'Converted media remains in Media and Tasks':"state.filter='Media';const xm=item('study');xm.task=true;const media=matches(xm);state.filter='Tasks';media&&matches(xm)",
 'Conversion keeps receipt and content':"const before=JSON.stringify([item('feedback').id,item('feedback').text,item('feedback').date]);item('feedback').task=true;before===JSON.stringify([item('feedback').id,item('feedback').text,item('feedback').date])",
 'Recurring completion creates only one next':"toggleComplete('invoice');const next=item('invoice').next;toggleComplete('invoice');toggleComplete('invoice');state.items.filter(x=>x.previous==='invoice').length===1&&item('invoice').next===next",
 'Monthly recurrence retains month-end anchor':"recurrenceDate({repeat:'Monthly',recurrenceAnchor:'2026-08-31'})==='2026-10-31'",
 'Next recurrence has no copied attachments':"item(item('invoice').next).attachments.length===0",
 'Reminder timestamp survives rerender':"item('review').reminder='2026-10-02T14:00:00.000Z';const t=item('review').reminder;detailView();item('review').reminder===t",
 'Trash and restore preserve receipt':"const d=item('review').date;trash('review');const family=item('brief').deleted;restore('review');d===item('review').date&&!!family&&!item('brief').deleted",
 'Kept automatic copies survive retention':"item('auto0').kept=true;!retentionCandidates().some(x=>x.id==='auto0')",
 'Pinned automatic copies survive retention':"item('auto1').pinned=true;!retentionCandidates().some(x=>x.id==='auto1')",
 'Save failure rolls state back':"const p=state.project;failSave=true;change(()=>state.project='broken',false);failSave=false;state.project===p",
 'Day export ignores active filter':"state.filter='All';const a=exportText('Day');state.filter='Links';exportText('Day')===a",
 'Week export includes earlier original receipts':"state.date=TODAY;exportText('Week').includes('2026-09-28')",
 'Scratchpad conversion leaves text':"const text=state.notes['Northstar Studio'].text;state.project='Northstar Studio';createCapture(text,true);state.notes['Northstar Studio'].text===text",
 'Named snippet search preserves content':"const original=item('snippet').text;item('snippet').snippet='Friendly ending';item('snippet').text===original",
 'Search without source filter finds scratchpad':"state.query='conversation';state.filter='All';state.project='all';state.scope='All';state.source='all';searchResults();htmlNodes['#search-results'].innerHTML.includes('Scratchpad')",
 'Source-app refinement excludes scratchpad':"state.source='Mail';searchResults();!htmlNodes['#search-results'].innerHTML.includes('Scratchpad')",
 'Shelf membership removal keeps capture':"const n=state.items.length;item('study').shelf=false;state.items.length===n&&!item('study').deleted",
 'Raw user text is escaped':"esc('<img src=x onerror=alert(1)>').startsWith(String.fromCharCode(38))",
 'Checklist retains mixed-language content':"const text='שלום 日本語';item('review').checklist.push({text,done:false});item('review').checklist.at(-1).text===text"
}
for name,code in tests.items():
 try:
  # Each assertion has a fresh lexical scope while sharing intentional fixture state.
  split=code.rsplit(';',1)
  body=(split[0]+';return ('+split[1]+')') if len(split)==2 else 'return ('+code+')'
  check(name,c.run('(()=>{'+body+'})()')=='true')
 except Exception as e:check(name,False,str(e))
# Task-card interaction contracts: actual state transitions, persistence and failure handling.
t=context()
t.run('var taskNow=Date.now();Date.now=()=>taskNow;')
task_tests={
 'Capture conversion transforms in place without navigating':"const href=location.href;convertCapture('study');location.href===href&&card(item('study')).includes('class=\"task-card ')",
 'Converted task retains image, source, receipt, ID and media filter':"const x=item('study');state.filter='Media';x.id==='study'&&x.image.endsWith('northstar-study.svg')&&x.source==='Finder'&&x.date===TODAY&&matches(x)",
 'Task cards expose completion, timer, playback and calendar':"const html=taskCard(item('review'));['data-action=\"complete\"','data-action=\"task-duration\"','data-action=\"timer-toggle\"','data-action=\"task-schedule\"'].every(v=>html.includes(v))",
 'Task editor uses no select menus':"!taskDetailView(item('review')).includes('<select')",
 'Focus starts with persistent end timestamp':"toggleFocus('review');item('review').focus.endAt===taskNow+45*60000&&focusRemaining(item('review'))===2700",
 'Countdown derives remaining time after background delay':"taskNow+=75000;focusRemaining(item('review'))===2625",
 'Pause freezes exact remaining seconds':"toggleFocus('review');const paused=focusRemaining(item('review'));taskNow+=120000;focusRemaining(item('review'))===paused&&!item('review').focus.endAt",
 'Resume continues remaining duration':"toggleFocus('review');item('review').focus.endAt===taskNow+2625*1000",
 'Timer survives persisted state reload':"const target=item('review').focus.endAt;state=JSON.parse(storage[KEY]);item('review').focus.endAt===target&&focusRemaining(item('review'))===2625",
 'Timer expiry does not complete task or overwrite reminder':"item('review').reminder='2026-10-02T12:00';taskNow+=2626000;updateTaskTimers();item('review').focus.remaining===0&&!item('review').focus.endAt&&!item('review').completed&&item('review').reminder==='2026-10-02T12:00'",
 'Finished timer can restart at full duration':"toggleFocus('review');focusRemaining(item('review'))===2700&&!!item('review').focus.endAt",
 'Completion stops focus; recurrence receives no timer':"toggleFocus('invoice');toggleComplete('invoice');!item('invoice').focus.endAt&&!item(item('invoice').next).focus",
 'Schedule writes workday/time and preserves receipt':"const date=item('study').date;updateTaskPlan('study',{planned:'2026-10-02',scheduledTime:'14:30'});item('study').date===date&&planLabel(item('study')).includes('14:30')",
 'Schedule updates retained draft without losing title':"state.drafts.study={title:'Keep my unsaved title'};updateTaskPlan('study',{planned:TODAY,scheduledTime:'10:00'});state.drafts.study.title==='Keep my unsaved title'&&state.drafts.study.planned===TODAY",
 'Failed timer save retains prior running timestamp':"const before=JSON.stringify(item('review').focus);failSave=true;toggleFocus('review');failSave=false;JSON.stringify(item('review').focus)===before",
 'Failed conversion retains capture state':"failSave=true;convertCapture('feedback');failSave=false;!item('feedback').task",
 'Task formatting includes hours and minutes':"durationLabel(90)==='1h 30m'&&focusClock({effort:90})==='01:30:00'",
 'Duration form saves hours and minutes as a new timed session':"taskEditor={id:'review',kind:'duration',startAfter:true};submitTaskTiming({preventDefault(){},target:{id:'task-duration-form',elements:{hours:{value:'1'},minutes:{value:'15'}}}});item('review').effort===75&&focusRemaining(item('review'))===4500",
 'Invalid duration retains original timer':"const before=JSON.stringify(item('review'));submitTaskTiming({preventDefault(){},target:{id:'task-duration-form',elements:{hours:{value:'1'},minutes:{value:'60'}}}});JSON.stringify(item('review'))===before",
 'Schedule form persists optional time':"taskEditor={id:'review',kind:'schedule'};submitTaskTiming({preventDefault(){},target:{id:'task-schedule-form',elements:{planned:{value:'2026-10-03'},scheduledTime:{value:'11:45'}}}});item('review').planned==='2026-10-03'&&item('review').scheduledTime==='11:45'",
 'Undo conversion returns the original media card':"handleTaskAction({dataset:{action:'undo-task-conversion'}});!item('study').task&&card(item('study')).includes('class=\"card card-media ')",
 'Converted task source details retain file group':"const x=item('batch');x.task=true;taskDetailView(x).includes('Northstar — client feedback')&&taskDetailView(x).includes('Review copy')"
}
for name,code in task_tests.items():
 try:
  split=code.rsplit(';',1)
  body=(split[0]+';return ('+split[1]+')') if len(split)==2 else 'return ('+code+')'
  check(name,t.run('(()=>{'+body+'})()')=='true')
 except Exception as e:check(name,False,str(e))

# Source/destination receipts are independent from clipboard copies and task plans.
p=context('inbox')
trail_tests={
 'Existing captures do not gain invented paste destinations':"pasteReceipts(item('feedback')).length===0&&contentTrail(item('feedback')).includes('No pastes')",
 'Known source apps render locally preserved marks':"contentTrail(item('feedback')).includes('app-icons/mail.png')&&contentTrail(item('link')).includes('app-icons/safari.png')",
 'Unknown source stays unknown instead of claiming DaBin':"captureOrigin(item('followup')).name==='Unknown source'&&contentTrail(item('followup')).includes('app-mark-unknown')",
 'Native bundle identifiers resolve real app identity':"captureOrigin({sourceApplicationBundleIdentifier:'com.apple.mail'}).id==='mail'",
 'Manual destination receipts persist with explicit attribution':"recordManualPaste('feedback','slack');const r=pasteReceipts(item('feedback'))[0];r.kind==='manual'&&r.app==='slack'&&JSON.parse(storage[KEY]).items.find(x=>x.id==='feedback').pasteHistory.length===1",
 'Repeated pastes retain both receipts but one destination logo':"recordManualPaste('feedback','slack');pasteReceipts(item('feedback')).length===2&&pasteDestinations(item('feedback')).length===1&&pasteDestinations(item('feedback'))[0].count===2",
 'Capture conversion keeps the exact paste history':"const before=JSON.stringify(item('feedback').pasteHistory);convertCapture('feedback');JSON.stringify(item('feedback').pasteHistory)===before&&taskCard(item('feedback')).includes('app-icons/slack.png')",
 'Conversion undo keeps the paste history':"handleTaskAction({dataset:{action:'undo-task-conversion'}});!item('feedback').task&&pasteReceipts(item('feedback')).length===2",
 'Task detail exposes the trail outside collapsed attachments':"taskDetailView(item('review')).indexOf('trail-detail')<taskDetailView(item('review')).indexOf('task-fold')",
 'Failed destination save rolls back its receipt':"const before=JSON.stringify(item('feedback').pasteHistory);failSave=true;recordManualPaste('feedback','notes');failSave=false;JSON.stringify(item('feedback').pasteHistory)===before",
 'Destination names and markup are escaped':"recordManualPaste('feedback','<img onerror=alert(1)>');const html=contentTrail(item('feedback'));html.includes(String.fromCharCode(38)+'lt'+String.fromCharCode(59)+'img')&&!html.includes('<img onerror')",
 'Invalid receipt kinds never masquerade as confirmed pastes':"item('study').pasteHistory=[{app:'mail',kind:'copied',at:'2026-09-30T12:00:00Z'}];pasteReceipts(item('study')).length===0",
 'Confirmed receipts cannot be removed as manual entries':"item('study').pasteHistory=[{id:'confirmed',app:'mail',kind:'confirmed',at:'2026-09-30T12:00:00Z'}];!removeManualPaste('study','confirmed')&&pasteReceipts(item('study')).length===1",
 'User-recorded receipt removal preserves the other events':"const r=pasteReceipts(item('feedback'))[0];const before=pasteReceipts(item('feedback')).length;removeManualPaste('feedback',r.id);pasteReceipts(item('feedback')).length===before-1",
 'Recurrence starts with no pastes from the previous occurrence':"recordManualPaste('invoice','mail');toggleComplete('invoice');pasteReceipts(item('invoice')).length===1&&pasteReceipts(item(item('invoice').next)).length===0",
 'Empty app names do not write receipts':"!recordManualPaste('feedback','   ')",
 'Unknown destination uses a neutral mark rather than a fake logo':"recordManualPaste('feedback','Unlisted Product');contentTrail(item('feedback')).includes('app-mark-unknown')",
 'Long trails collapse to three app marks and an overflow count':"for(const app of ['mail','notes','finder','safari'])recordManualPaste('feedback',app);contentTrail(item('feedback')).includes('trail-overflow')"
}
for name,code in trail_tests.items():
 try:
  split=code.rsplit(';',1)
  body=(split[0]+';return ('+split[1]+')') if len(split)==2 else 'return ('+code+')'
  check(name,p.run('(()=>{'+body+'})()')=='true')
 except Exception as e:check(name,False,str(e))
for app in ['mail','notes','finder','safari','chrome','slack']:
 check('Local app mark: '+app,(SRC/'assets/app-icons'/str(app+'.png')).is_file())
check('Clipboard copy does not create paste events','recordManualPaste' not in scripts['interactions.js'].split("case 'copy':",1)[1].split("case 'keep':",1)[0])

# The robot now shares Inbox composition; persistence must clear only the saved draft.
r=context('robot')
check('Robot capture clears shared Inbox draft after persistence',r.run("state.drafts.inbox={text:'Keep this thought'};createCapture('Keep this thought');!state.drafts.inbox&&state.items[0].text==='Keep this thought'")=='true')
check('Failed robot save preserves shared Inbox draft',r.run("state.drafts.inbox={text:'Keep until saved'};failSave=true;createCapture('Keep until saved');!!state.drafts.inbox&&state.drafts.inbox.text==='Keep until saved'")=='true')

# Execute the ZIP writer against local fixture files, then verify bytes with Python.
import io,zipfile
z=context('shelf')
z.run(scripts['events.js'][scripts['events.js'].index('function crc32'):scripts['events.js'].rindex('render();try')])
files={str(p.relative_to(ROOT)):list(p.read_bytes()) for p in (SRC/'assets').glob('*') if p.is_file()}
z.run('var assetBytes='+json.dumps(files)+';')
z.run("""
var TextEncoder=class{encode(s){return Uint8Array.from(unescape(encodeURIComponent(s)),c=>c.charCodeAt(0))}};
var Blob=class{constructor(parts,options){this.parts=parts}};
var URL={createObjectURL(b){window.zipBytes=b.parts.flatMap(p=>Array.from(p));return 'blob:fixture'},revokeObjectURL(){}};
var fetch=async path=>({ok:!!assetBytes[path],arrayBuffer:async()=>Uint8Array.from(assetBytes[path]).buffer});
document.createElement=()=>({click(){}});
state.project='Northstar Studio';state.filter='Links';exportShelf();
""")
try:
 raw=z.run('JSON.stringify(window.zipBytes)')
 data=bytes(json.loads(raw));package=zipfile.ZipFile(io.BytesIO(data))
 check('Shelf ZIP verifies CRC and includes full project despite Links filter',package.testzip() is None and len(package.namelist())==3)
 check('Shelf ZIP retains SVG file bytes',package.read('Northstar_direction-02_EN-HE-日本語.svg')==(SRC/'assets/northstar-study.svg').read_bytes())
except Exception as e:check('Shelf ZIP execution',False,str(e))

# Contrast audit: source presets and extreme custom choices, both appearances.
for dark in [False,True]:
 for color in ['#6D5387','#386A9A','#287875','#47763E','#A34D73','#956515','#000000','#ffffff','#00ff00','#ffff00']:
  c.run('state.settings.dark='+str(dark).lower()+';state.settings.accent='+json.dumps(color)+';applyTheme();')
  styles=json.loads(c.run('JSON.stringify(document.documentElement.style)'))
  rgb=[int(n)/255 for n in re.findall(r'\d+',styles['--accent'])]
  def lum(v):return sum((n/12.92 if n<=.04045 else ((n+.055)/1.055)**2.4)*w for n,w in zip(v,[.2126,.7152,.0722]))
  def hexrgb(h):return [int(h[i:i+2],16)/255 for i in [1,3,5]]
  def ratio(a,b):
   x,y=lum(a),lum(b);return (max(x,y)+.05)/(min(x,y)+.05)
  bg=hexrgb('#2d2a30' if dark else '#f3f1f5')
  check('Accent text contrast: '+color+(' dark' if dark else ' light'),ratio(rgb,bg)>=4.5,str(round(ratio(rgb,bg),2)))
  on=hexrgb(styles['--on-accent'])
  check('Primary button contrast: '+color+(' dark' if dark else ' light'),ratio(rgb,on)>=4.5,str(round(ratio(rgb,on),2)))

exec(compile((SRC/'qa/responsive_checks.py').read_text(),str(SRC/'qa/responsive_checks.py'),'exec'))

for p in ROOT.glob('*.html'):
 s=p.read_text();check('Document structure: '+p.name,s.lower().startswith('<!doctype html>') and '</html>' in s and s.count('<script>')==s.count('</script>'))
(SRC/'qa-results.json').write_text(json.dumps(results,indent=2))
failed=[x for x in results if not x['passed']]
print(json.dumps({'passed':len(results)-len(failed),'failed':failed},indent=2))
raise SystemExit(bool(failed))
