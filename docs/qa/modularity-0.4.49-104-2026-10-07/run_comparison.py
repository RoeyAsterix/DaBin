#!/usr/bin/env python3
"""Separate diagnostic ABBA short workload; not a replacement for full/sustained QA."""
from pathlib import Path
import datetime,fcntl,hashlib,json,os,subprocess,sys,time
ROOT=Path('/private/tmp/dabin-modularity-comparison-20261007')
OLD=Path('/private/tmp/dabin-speed-stability-20261007-070033')
NEW=Path('/private/tmp/dabin-modularity-20261007')
if ROOT.exists(): raise SystemExit('Comparison output already exists; do not overwrite evidence')
lock=open('/private/tmp/dabin-speed-stability-qa.lock','a+')
try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:raise SystemExit('Another QA campaign holds the lock; no comparison started')
ROOT.mkdir();lock.seek(0);lock.truncate();lock.write(str(os.getpid())+'\n');lock.flush()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
freezes={label:json.loads((r/'source-freeze.json').read_text()) for label,r in [('baseline',OLD),('refactor',NEW)]}
bases={'baseline':OLD/'snapshot','refactor':NEW/'working'}
def matched(label):
 return all((bases[label]/p).is_file() and sha(bases[label]/p)==h for p,h in freezes[label]['fullSnapshotInputs'].items())
if not all(matched(label) for label in bases):raise SystemExit('A frozen comparison input changed')
if sha(bases['baseline']/'native/Tests/WorkspaceZoomPerformanceTests.swift')!=sha(bases['refactor']/'native/Tests/WorkspaceZoomPerformanceTests.swift'):
 raise SystemExit('Performance harness differs; no controlled comparison')
results=[];start=time.monotonic()
env={k:v for k,v in os.environ.items() if not k.startswith(('DABIN_','DYLD_'))};env['PYTHONDONTWRITEBYTECODE']='1'
try:
 for number,label in enumerate(['baseline','refactor','refactor','baseline'],1):
  if not matched(label):raise SystemExit('Frozen source changed before comparison stage')
  native=bases[label]/'native';out=ROOT/(str(number)+'-'+label);out.mkdir()
  runenv=env|{'DABIN_ZOOM_PERFORMANCE_SECONDS':'30','DABIN_ZOOM_PERFORMANCE_QA_OUTPUT':str(out/'metrics')}
  args=[sys.executable,'-B',str(native/'scripts/run_qa.py'),'--distribution','app-store','--configuration','Release','--only','WorkspaceZoomPerformanceTests','--timeout','120']
  launch={'startedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':str(native),'productionFingerprint':freezes[label]['productionFingerprint'],'arguments':args,'controlledEnvironment':{k:v for k,v in runenv.items() if k.startswith('DABIN_')},'scope':'Diagnostic short ABBA comparison; does not supersede full or600-second results.'}
  (out/'launch.json').write_text(json.dumps(launch,indent=2)+'\n');print('START '+str(number)+' '+label,flush=True)
  t=time.monotonic()
  with (out/'runner.log').open('w') as stream:p=subprocess.run(args,cwd=native,env=runenv,stdout=stream,stderr=subprocess.STDOUT)
  report=native/'build/qa/latest-run-app-store.json';data=json.loads(report.read_text())
  if data['startedAtUTC']<launch['startedAtUTC']:raise SystemExit('Comparison report predates launch')
  (out/'native-report.json').write_bytes(report.read_bytes())
  for suite in data['suites']:
   if suite['name']=='WorkspaceZoomPerformanceTests':
    for name in ['log']:
     if suite.get(name):(out/'suite.log').write_bytes((native/suite[name]).read_bytes())
    if suite.get('compile',{}).get('log'):(out/'suite-compile.log').write_bytes((native/suite['compile']['log']).read_bytes())
  metric=json.loads((out/'metrics/performance.json').read_text())
  result={'number':number,'source':label,'productionFingerprint':freezes[label]['productionFingerprint'],'exitCode':p.returncode,'seconds':round(time.monotonic()-t,3),'sourceUnchanged':matched(label),'inputP95Milliseconds':metric['inputToLayoutP95Milliseconds'],'steadyTimerP95Milliseconds':metric['steadyZoomTimerP95Milliseconds'],'performanceGates':metric['performanceGates'],'report':str(out/'native-report.json'),'metrics':str(out/'metrics/performance.json')}
  results.append(result);(ROOT/'progress.json').write_text(json.dumps(results,indent=2)+'\n');print('FINISH '+json.dumps(result),flush=True)
finally:
 record={'finishedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Unprofiled diagnostic short ABBA comparison; original workload/gates preserved. It does not certify sustained performance or prove a causal attribution.','harnessSHA256':sha(bases['refactor']/'native/Tests/WorkspaceZoomPerformanceTests.swift'),'totalSeconds':round(time.monotonic()-start,3),'results':results,'allComparisonInputsUnchanged':all(matched(label) for label in bases)}
 (ROOT/'comparison-result.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
 lock.seek(0);lock.truncate();lock.flush();fcntl.flock(lock,fcntl.LOCK_UN)
print('COMPARISON '+str(ROOT/'comparison-result.json'),flush=True)
