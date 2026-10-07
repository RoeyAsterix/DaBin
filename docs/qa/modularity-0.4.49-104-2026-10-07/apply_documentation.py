#!/usr/bin/env python3
"""Apply reviewed doc corrections after all frozen workloads; never alter code."""
from pathlib import Path
import datetime,hashlib,importlib.util,json,plistlib,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parent
REPO=Path('/Users/roeylibfeld/Documents/KARI Creatives/DaBin')
OUT=ROOT/'evidence'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
freeze=json.loads((ROOT/'source-freeze.json').read_text())
verification=json.loads((ROOT/'verification-collected.json').read_text())
if verification['pendingArtifacts'] or verification['integrityProblems']:
 raise SystemExit('Verification is incomplete or has integrity mismatches')
if not OUT.is_dir(): raise SystemExit('Preserved evidence missing')
changes=[p for p,h in freeze['fullSnapshotInputs'].items() if not (REPO/p).is_file() or sha(REPO/p)!=h]
if changes: raise SystemExit('Concurrent input drift before documentation write: '+str(changes))
path='native/ARCHITECTURE.md'
target=REPO/path
prepared=ROOT/'ARCHITECTURE-final.md'
expected='2129679434f4dbe7b79b5948a38c2a4b278862239dc7640e88bbbad54440c9fa'
if target.is_symlink() or sha(prepared)!=expected: raise SystemExit('Documentation target/preparation guard failed')
before=sha(target)
target.write_bytes(prepared.read_bytes())
remaining=[p for p,h in freeze['fullSnapshotInputs'].items() if not (REPO/p).is_file() or sha(REPO/p)!=h]
if remaining!=[path]: raise SystemExit('Unexpected post-documentation drift: '+str(remaining))
spec=importlib.util.spec_from_file_location('final_inventory',REPO/'native/scripts/project_inventory.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
inputs=module.build_inventory()
fp=hashlib.sha256(json.dumps(inputs,sort_keys=True,separators=(',',':')).encode()).hexdigest()
if inputs!=freeze['productionInputs'] or fp!=freeze['productionFingerprint']:
 raise SystemExit('Production inputs changed after documentation write')
info=plistlib.loads((REPO/'native/Resources/Info.plist').read_bytes())
if info['CFBundleShortVersionString']!=freeze['version'] or info['CFBundleVersion']!=freeze['build']:
 raise SystemExit('Current version/build changed')
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
doc={'appliedAtUTC':now,'scope':'Documentation corrections after frozen verification completed; no production/test/config input changes.','path':path,'beforeSHA256':before,'afterSHA256':sha(target),'patchSHA256':sha(ROOT/'documentation-corrections.patch'),'corrections':['current primary tab names','visible board at every cold launch','enabled full screen/recording global shortcuts'],'productionFingerprintUnchanged':True}
final={'verifiedAtUTC':now,'version':freeze['version'],'build':freeze['build'],'productionFingerprint':fp,'productionInputsMatched':True,'allFrozenInputsMatchedExceptDocumentedCorrections':True,'matchedInputCount':len(freeze['fullSnapshotInputs'])-1,'documentationDifferences':[{k:doc[k] for k in ['path','beforeSHA256','afterSHA256']}],'codeTestAndConfigurationInputsUnchanged':True,'noDistributionSigningInstallArchiveOrUploadPerformed':True}
for name,data in [('documentation-corrections.json',doc),('final-live-verification.json',final)]:
 (ROOT/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
 (OUT/name).write_bytes((ROOT/name).read_bytes())
summary=json.loads((OUT/'verification-summary.json').read_text())
summary['postVerificationDocumentationReceipt']={'path':'documentation-corrections.json','sha256':sha(OUT/'documentation-corrections.json')}
summary['finalLiveVerificationReceipt']={'path':'final-live-verification.json','sha256':sha(OUT/'final-live-verification.json')}
(OUT/'verification-summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps(final,indent=2))
