#!/usr/bin/env python3
import datetime,fcntl,hashlib,json,os,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
NATIVE=ROOT/'snapshot/native'
FREEZE=json.loads((ROOT/'source-freeze.json').read_text())
ENV={k:v for k,v in os.environ.items() if not k.startswith(('DABIN_','DYLD_'))}
ENV['PYTHONDONTWRITEBYTECODE']='1'
OUTPUT_KEYS=['DABIN_TIMESTAMP_QA_DIR','DABIN_CAPTION_SELECTION_QA_OUTPUT','DABIN_CARD_DELETION_QA_OUTPUT','DABIN_CAPTURE_DETAIL_READABILITY_QA_OUTPUT','DABIN_AUTO_RECORD_RENDER_DIR','DABIN_CAPTURE_SIGN_RENDER_DIR','DABIN_HEADER_QA_DIR','DABIN_NATIVE_TOOLTIP_QA_OUTPUT','DABIN_ICON_QA_DIR','DABIN_CAPTURE_DETAIL_NAVIGATION_QA_OUTPUT','DABIN_EXTENDED_QA_OUTPUT','DABIN_EXTENDED_MEDIA_QA_OUTPUT','DABIN_PROJECT_WORKSPACE_VIEW_QA_OUTPUT','DABIN_DAY_LAYOUT_QA_OUTPUT','DABIN_SEARCH_QA_DIR','DABIN_WEEK_LAYOUT_QA_OUTPUT','DABIN_COMPANION_QA_OUTPUT','DABIN_EXPLORER_CARD_QA_OUTPUT','DABIN_ICON_PRESENTATION_QA_DIR','DABIN_TASK_PLAN_QA_OUTPUT','DABIN_PROJECT_WORKSPACE_CARD_QA_OUTPUT','DABIN_RECORDING_SIGN_RENDER_DIR','DABIN_ZOOM_LAYOUT_QA_OUTPUT','DABIN_SNIPPET_NAMING_QA_OUTPUT','DABIN_TODAY_CARD_QA_OUTPUT','DABIN_WORKSPACE_WINDOW_QA_OUTPUT','DABIN_VISUAL_ANIMATION_STRESS_OUTPUT','DABIN_ZOOM_PERFORMANCE_QA_OUTPUT']
LOCK=open('/private/tmp/dabin-speed-stability-qa.lock','a+')
try: fcntl.flock(LOCK,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('Another owned speed/stability campaign is running; no tests started')
LOCK.seek(0);LOCK.truncate();LOCK.write(str(os.getpid())+'\n');LOCK.flush()
START=time.monotonic(); stages=[]
def snapshot_matches():
 return all((ROOT/'snapshot'/p).is_file() and hashlib.sha256((ROOT/'snapshot'/p).read_bytes()).hexdigest()==v for p,v in FREEZE['fullSnapshotInputs'].items())
def cache_receipts(label):
 result={}
 for p in sorted((NATIVE/'build/qa-cache').glob('*/**/*ready.json')):
  try:
   d=json.loads(p.read_text());valid=all((p.parent/n).is_file() and hashlib.sha256((p.parent/n).read_bytes()).hexdigest()==h for n,h in d['outputs'].items())
   result[str(p.relative_to(NATIVE))]={'receiptSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'outputs':d['outputs'],'outputHashesVerified':valid}
  except (OSError,KeyError,ValueError): result[str(p.relative_to(NATIVE))]={'outputHashesVerified':False}
 (ROOT/(label+'-compiled-output-verification.json')).write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 return result

def run(label,args,zoom_seconds=None):
 if not snapshot_matches(): raise SystemExit('Frozen inputs changed; stop campaign')
 output=ROOT/'outputs'/label;output.mkdir(parents=True)
 env=ENV.copy()
 if zoom_seconds is not None:
  for key in OUTPUT_KEYS: env[key]=str(output/key.removeprefix('DABIN_').lower())
  env['DABIN_ZOOM_PERFORMANCE_SECONDS']=str(zoom_seconds)
 launch={'stage':label,'arguments':args,'cwd':str(NATIVE),'startedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'productionFingerprint':FREEZE['productionFingerprint'],'controlledEnvironment':{k:v for k,v in env.items() if k.startswith('DABIN_') or k=='PYTHONDONTWRITEBYTECODE'},'unsetOverrides':['DABIN_SEARCH_QA_SKIP_KEYBOARD','DABIN_ZOOM_PERFORMANCE_FIXED_DATA','DABIN_NATIVE_DRAG_MANUAL','all inherited DYLD_*'],'snapshotUnchanged':True}
 (ROOT/(label+'-launch.json')).write_text(json.dumps(launch,indent=2)+'\n')
 started=time.monotonic();print('START '+label,flush=True)
 with (ROOT/(label+'.log')).open('w') as stream:
  p=subprocess.run(args,cwd=NATIVE,env=env,stdout=stream,stderr=subprocess.STDOUT)
 result={'stage':label,'exitCode':p.returncode,'seconds':round(time.monotonic()-started,3),'log':str(ROOT/(label+'.log')),'snapshotUnchanged':snapshot_matches(),'finishedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 if zoom_seconds is not None:
  latest=NATIVE/'build/qa/latest-run-app-store.json'
  if latest.exists():
   report=json.loads(latest.read_text())
   if report['startedAtUTC']>=launch['startedAtUTC']:
    target=ROOT/(label+'-native-report.json');target.write_bytes(latest.read_bytes())
    result.update(reportPath=str(target),passedSuites=report['passedSuites'],failedSuites=report['failedSuites'],reportStatus=report['status'],reportCoverage=report['coverage'])
    cache_receipts(label)
 stages.append(result);(ROOT/'campaign-progress.json').write_text(json.dumps({'stages':stages,'elapsedSeconds':round(time.monotonic()-START,3)},indent=2)+'\n')
 print('FINISH '+json.dumps(result),flush=True);return result

try:
 full=run('full-native',[sys.executable,'-B',str(NATIVE/'scripts/run_qa.py'),'--distribution','app-store','--configuration','Release'],30)
 report=json.loads(Path(full['reportPath']).read_text()) if full.get('reportPath') else {}
 if report.get('productionModule',{}).get('status')=='passed' and snapshot_matches():
  run('sustained-speed',[sys.executable,'-B',str(NATIVE/'scripts/run_qa.py'),'--distribution','app-store','--configuration','Release','--only','WorkspaceZoomPerformanceTests','--timeout','900'],600)
 else:
  stages.append({'stage':'sustained-speed','status':'blocked_by_missing_or_failed_production_module'})
 run('python-tool-tests',[sys.executable,'-B','-m','unittest','discover','-s','Tests','-p','test_*.py','-v'])
 run('offline-packaging',[sys.executable,'-B',str(NATIVE/'scripts/test_app_store_preflight.py')])
 run('deterministic-project',[sys.executable,'-B',str(NATIVE/'scripts/generate_project.py'),'--check'])
finally:
 result={'finishedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsedSeconds':round(time.monotonic()-START,3),'productionFingerprint':FREEZE['productionFingerprint'],'version':FREEZE['version'],'build':FREEZE['build'],'stages':stages,'snapshotUnchanged':snapshot_matches()}
 (ROOT/'campaign-result.json').write_text(json.dumps(result,indent=2)+'\n')
 LOCK.seek(0);LOCK.truncate();LOCK.flush();fcntl.flock(LOCK,fcntl.LOCK_UN)
print('CAMPAIGN '+str(ROOT/'campaign-result.json'),flush=True)
