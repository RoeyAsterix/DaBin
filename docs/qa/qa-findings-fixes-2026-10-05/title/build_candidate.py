#!/usr/bin/env python3
"""Compile the isolated native title candidate. Never launch any GUI process."""
from pathlib import Path
import argparse, datetime, hashlib, json, plistlib, shlex, shutil, subprocess, time
parser=argparse.ArgumentParser();parser.add_argument("--test-only",action="store_true");args=parser.parse_args()
base=Path(__file__).resolve().parent
native=base.parents[3]/'native'
fixture=base/'fixture/native'; sources=fixture/'Sources/DaBin'; sources.mkdir(parents=True,exist_ok=True)
resources=fixture/'Resources'
if resources.exists(): shutil.rmtree(resources)
shutil.copytree(native/'Resources',resources)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
previous=base/'candidate-manifest.json'
if previous.exists():
    prior=json.loads(previous.read_text())
    baseline=prior['baselineProductionSourceSHA256']
    if args.test_only:
        assert prior['candidateDetailSHA256']==sha(base/'DetailScreen.swift'), 'test-only requires unchanged candidate source'
        assert prior['compiledLibrarySHA256']==sha(base/'build/libDaBinTestCore.dylib'), 'cached candidate library changed'
        assert prior['compiledModuleSHA256']==sha(base/'build/DaBinTestCore.swiftmodule'), 'cached candidate module changed'
else:
    baseline={str(p.relative_to(native)):sha(p) for p in sorted((native/'Sources/DaBin').glob('*.swift'))}
    for source in (native/'Sources/DaBin').glob('*.swift'):shutil.copyfile(source,sources/source.name)
shutil.copyfile(base/'DetailScreen.swift',sources/'DetailScreen.swift')
module=base/'build';module.mkdir(exist_ok=True)
app=base/'apps/TaskPlanTitleCandidate.app'; macos=app/'Contents/MacOS'; payload=app/'Contents/Resources'
macos.mkdir(parents=True,exist_ok=True);payload.mkdir(exist_ok=True)
for name in ['AppIcon.icns','PrivacyInfo.xcprivacy','PrivacyPolicy.md','robot.svg']:shutil.copyfile(resources/name,payload/name)
info=plistlib.loads((resources/'Info.plist').read_bytes());info.update(CFBundleExecutable='TaskPlanInteractionTests',CFBundleIdentifier='com.dabin.mac.qa.title-candidate',CFBundleName='TaskPlanTitleCandidate',LSUIElement=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
wrapper=base/'fixture/TaskPlanInteractionTests.swift';wrapper.write_text('@testable import DaBinTestCore\n'+(base/'TaskPlanInteractionTests.swift').read_text())
common=['xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(module/'ModuleCache'),'-warnings-as-errors','-parse-as-library','-O','-whole-module-optimization']
library=module/'libDaBinTestCore.dylib';executable=macos/'TaskPlanInteractionTests'
production=[*common,'-emit-library','-emit-module','-enable-testing','-module-name','DaBinTestCore','-emit-module-path',str(module/'DaBinTestCore.swiftmodule'),'-Xlinker','-install_name','-Xlinker',str(library),*[str(p) for p in sorted(sources.glob('*.swift')) if p.name!='DaBinMain.swift'],'-o',str(library)]
test=[*common,'-I',str(module),'-L',str(module),'-lDaBinTestCore','-Xlinker','-rpath','-Xlinker',str(module),str(wrapper),'-o',str(executable)]
manifest={'schemaVersion':1,'createdAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Isolated copied-source native title candidate and tightly relevant TaskPlan fixture; no live Sources/shared tests edited; compile-only, no GUI runtime',
'baselineNativeRoot':str(native),'baselineProductionSourceSHA256':baseline,'candidateProductionSourceSHA256':{str(p.relative_to(fixture)):sha(p) for p in sorted(sources.glob('*.swift'))},
'candidateDetailSHA256':sha(base/'DetailScreen.swift'),'baselineDetailSHA256':sha(native/'Sources/DaBin/DetailScreen.swift'),'candidateTaskPlanSHA256':sha(base/'TaskPlanInteractionTests.swift'),'baselineTaskPlanSHA256':sha(native/'Tests/TaskPlanInteractionTests.swift'),
'configuration':'Release','distribution':'app-store','compileDefinitions':[],'moduleDirectory':str(module),'appBundle':str(app),'executable':str(executable),'runtimeStatus':'not_run_by_author',
'commands':{'productionModule':production,'taskPlan':test},'shellCommands':{'productionModule':shlex.join(production),'taskPlan':shlex.join(test)},
'recommendedRuntimeCommand':[str(executable)],'recommendedRuntimeWorkingDirectory':str(fixture),'recommendedRuntimeEnvironment':{'DABIN_TASK_PLAN_QA_OUTPUT':str(base/'renders'),'DYLD_LIBRARY_PATH':str(module)},
'resourceInputs':{str(p.relative_to(fixture)):sha(p) for p in sorted(resources.rglob('*')) if p.is_file()},'compileResults':[]}
path=base/'candidate-manifest.json'
def save():path.write_text(json.dumps(manifest,indent=2)+'\n')
save()
if args.test_only:
 manifest['compileResults'].append({'name':'productionModule','status':'reused_verified_compiled_candidate','librarySHA256':prior['compiledLibrarySHA256'],'moduleSHA256':prior['compiledModuleSHA256']});save()
for name,command in ([('taskPlan',test)] if args.test_only else [('productionModule',production),('taskPlan',test)]):
 started=time.monotonic();log=base/(name+'-compile.log')
 with log.open('w') as out:
  try:result=subprocess.run(command,cwd=fixture,stdout=out,stderr=subprocess.STDOUT,timeout=180)
  except subprocess.TimeoutExpired:manifest['compileResults'].append({'name':name,'status':'timed_out','log':str(log)});save();raise
 manifest['compileResults'].append({'name':name,'status':'passed' if result.returncode==0 else 'failed','exitCode':result.returncode,'seconds':round(time.monotonic()-started,3),'log':str(log),'logSHA256':sha(log)})
 save();print(name,manifest['compileResults'][-1]['status'],flush=True)
 if result.returncode:raise SystemExit(result.returncode)
manifest['compiledLibrarySHA256']=sha(library);manifest['compiledModuleSHA256']=sha(module/'DaBinTestCore.swiftmodule');manifest['executableSHA256']=sha(executable)
manifest['finishedAtUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();manifest['status']='compiled_not_run';save();print('MANIFEST',path,flush=True)
