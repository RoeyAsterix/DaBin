#!/usr/bin/env python3
"""Preserve completed, hash-verified QA evidence; no builds or source edits."""
from pathlib import Path
import datetime, hashlib, json, shutil, zipfile
ROOT=Path(__file__).resolve().parent
COMPARISON=Path('/private/tmp/dabin-modularity-comparison-20261007')
OUT=ROOT/'evidence'
STAGE=ROOT/'evidence.preparing'
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
verification=json.loads((ROOT/'verification-collected.json').read_text())
if verification['pendingArtifacts'] or verification['integrityProblems']:
    raise SystemExit('Final verification is incomplete or has integrity mismatches')
if verification['collectionStatus'] not in ['complete','complete_with_native_failures']:
    raise SystemExit('Unexpected collection status')
if OUT.exists() or STAGE.exists(): raise SystemExit('Evidence destination/staging already exists; inspect it before replacing')
small=[
 'baseline.json','source-freeze.json','owned-changes.json','applied-refactor.json','diff-summary.json',
 'refactor.patch','documentation-corrections.patch',
 'focused-regression-native-report.json','focused-regression-launch.json',
 'focused-regression-compiled-output-verification.json','campaign-result.json',
 'full-native-native-report.json','full-native-launch.json',
 'sustained-speed-native-report.json','sustained-speed-launch.json',
 'full-campaign-result.json','unsigned-store-build-launch.json','deterministic-project-launch.json',
 'python-tool-tests-result.json','offline-packaging-result.json',
 'verification-artifact-hashes.json',
 'collect_verification.py','run_focused.py','run_full.py','preserve_evidence.py','run_comparison.py',
 'performance-review.md','comparison-verification.json'
]
index=json.loads((ROOT/'verification-artifact-hashes.json').read_text())['artifacts']
owned=json.loads((ROOT/'owned-changes.json').read_text())
before={}
for name,record in owned.items():
 if record['before'] is None: continue
 p=ROOT/'before'/name
 if Path(name).is_absolute() or '..' in Path(name).parts or not p.resolve().is_relative_to((ROOT/'before').resolve()):
  raise SystemExit('Unsafe before member: '+name)
 if not p.is_file() or sha(p)!=record['before']: raise SystemExit('Original input mismatch: '+name)
 before[name]=p
if len(before)!=12: raise SystemExit('Unexpected original input count')
for name,record in sorted(index.items()):
 p=ROOT/name
 if Path(name).is_absolute() or '..' in Path(name).parts or not p.resolve().is_relative_to(ROOT.resolve()):
  raise SystemExit('Unsafe archive member: '+name)
 if not p.is_file() or sha(p)!=record['sha256']: raise SystemExit('Evidence changed since collection: '+name)
for name in small:
 if not (ROOT/name).is_file(): raise SystemExit('Required evidence missing: '+name)
comparison=json.loads((COMPARISON/'comparison-result.json').read_text())
if comparison['allComparisonInputsUnchanged'] is not True or [r['source'] for r in comparison['results']]!=['baseline','refactor','refactor','baseline']:
 raise SystemExit('Incomplete or changed diagnostic comparison')
comparison_index={str(p.relative_to(COMPARISON)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in sorted(COMPARISON.rglob('*')) if p.is_file() and p.suffix in ['.json','.log','.txt']}
STAGE.mkdir()
for name in small:
 p=ROOT/name
 if not p.is_file(): raise SystemExit('Required evidence missing: '+name)
 shutil.copyfile(p,STAGE/name)
for label in ['full-native','sustained-speed']:
 shutil.copyfile(ROOT/'outputs'/label/'zoom_performance_qa_output/performance.json',STAGE/(label+'-performance.json'))
shutil.copyfile(COMPARISON/'comparison-result.json',STAGE/'comparison-result.json')
(STAGE/'comparison-artifact-hashes.json').write_text(json.dumps(comparison_index,indent=2,sort_keys=True)+'\n')
with zipfile.ZipFile(STAGE/'comparison-evidence.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
 for name,record in sorted(comparison_index.items()):
  p=COMPARISON/name
  if Path(name).is_absolute() or '..' in Path(name).parts or not p.resolve().is_relative_to(COMPARISON.resolve()) or sha(p)!=record['sha256']:
   raise SystemExit('Unsafe or changed diagnostic comparison artifact: '+name)
  archive.write(p,name)
with zipfile.ZipFile(STAGE/'raw-evidence.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
 for name,record in sorted(index.items()):
  p=ROOT/name
  if Path(name).is_absolute() or '..' in Path(name).parts or not p.resolve().is_relative_to(ROOT.resolve()):
   raise SystemExit('Unsafe archive member: '+name)
  if sha(p)!=record['sha256']: raise SystemExit('Evidence changed since collection: '+name)
  archive.write(p,name)
 archive.write(ROOT/'verification-collected.json','verification-collected.json')
 archive.write(ROOT/'verification-artifact-hashes.json','verification-artifact-hashes.json')
 for name,p in sorted(before.items()): archive.write(p,'before/'+name)
summary={
 'collectedAtUTC':verification['collectedAtUTC'],
 'collectionStatus':verification['collectionStatus'],
 'inputMatchesDescribeCollectionTimestamp':True,
 'integrityProblems':verification['integrityProblems'],
 'pendingArtifacts':verification['pendingArtifacts'],
 'scope':verification['scope'],
 'sourceVersion':verification['freeze']['data']['version'],
 'sourceBuild':verification['freeze']['data']['build'],
 'productionFingerprint':verification['freeze']['data']['productionFingerprint'],
 'frozenInputs':verification['frozenInputs'],
 'currentInventorySummary':{label:{k:d[k] for k in ['fingerprint','matchesFrozenProductionInputs','matchesFrozenProductionFingerprint','sourceCount','productionInputCount','nonFocusCount','windowCount','registryMatchesFrozen','uniqueRegistry','flatTestInventoryDifferences']} for label,d in verification['currentInventories'].items()},
 'nativeStageSummary':{label:{k:d[k] for k in ['requestedCount','statusCounts','reportRegistryMatchesFrozen','reportedFingerprintRecomputed','snapshotInputComparison','liveInputComparison','reportBelongsToLaunch']} for label,d in verification['nativeStages'].items()},
 'finalStageResults':verification['finalStageResults'],
 'compiledReceiptCount':verification['compiledReceipts']['count'],
 'compiledRequiredReceiptCount':verification['compiledReceipts']['requiredCount'],
 'toolingSummary':{k:verification['tooling'][k] for k in ['expectedThreeMetadataFailuresObserved','sixInventoryTestsPassed','offline33Passed']},
 'metadataMismatch':verification['metadataMismatch'],
 'allNativeAndBuildLogFindings':verification['allNativeAndBuildLogFindings'],
 'nativeWorkloadFailures':verification['nativeWorkloadFailures'],
 'failedNativeSuites':{label:[s['name'] for s in d['failedSuites']] for label,d in verification['nativeStages'].items()},
 'strictTimingObservations':[{'path':d['path'],**d['strictGateObservation']} for d in verification['metrics'] if 'strictGateObservation' in d],
 'unsignedStoreCandidates':[{k:v for k,v in d.items() if k!='data'}|{'receiptData':{k:v for k,v in d['data'].items() if k!='inputs'}} for d in verification['unsignedStoreCandidates']],
 'fullCollectorSHA256':sha(ROOT/'verification-collected.json'),
 'rawEvidence':{'file':'raw-evidence.zip','sha256':sha(STAGE/'raw-evidence.zip'),'indexedArtifactCount':len(index),'extraArchiveMembers':2+len(before),'binaryAndImageFixtureOutputsExcluded':True},
 'copiedArtifactHashes':{name:sha(STAGE/name) for name in small},
 'diagnosticComparison':{'result':'comparison-result.json','resultSHA256':sha(STAGE/'comparison-result.json'),'archive':'comparison-evidence.zip','archiveSHA256':sha(STAGE/'comparison-evidence.zip'),'hashIndex':'comparison-artifact-hashes.json','hashIndexSHA256':sha(STAGE/'comparison-artifact-hashes.json'),'certifiesSustainedPerformance':False},
}
(STAGE/'verification-summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
STAGE.rename(OUT)
print(json.dumps({'evidence':str(OUT),'files':len(list(OUT.iterdir())),'rawArchiveBytes':(OUT/'raw-evidence.zip').stat().st_size,'collectionStatus':verification['collectionStatus']},indent=2))
