#!/usr/bin/env python3
"""Build a synthetic review application against a frozen testable DaBin module.
Never rebuilds production sources, installs DaBin, or reads the personal archive.
"""
import argparse, hashlib, json, plistlib, shutil, subprocess
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--module',type=Path,required=True)
parser.add_argument('--stage',type=Path,default=Path('/private/tmp/DaBin-Review-Baseline-20260930'))
parser.add_argument('--variant',choices=('baseline','latest'),default='baseline')
args=parser.parse_args()
module=args.module.resolve();stage=args.stage.resolve()
if not str(stage).startswith('/private/tmp/DaBin-Review-'):
    raise SystemExit('Review build must live in the dedicated private temporary prefix.')
name='DaBin UX Review' if args.variant=='baseline' else 'DaBin UX Review Latest'
app=stage/(name+'.app');mac=app/'Contents/MacOS';frameworks=app/'Contents/Frameworks';resources=app/'Contents/Resources'
for path in (mac,frameworks,resources):path.mkdir(parents=True,exist_ok=True)
source=Path(__file__).with_name('ReviewFixture.swift' if args.variant=='baseline' else 'LatestReviewFixture.swift').resolve()
subprocess.run(['xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-parse-as-library','-warnings-as-errors','-I',str(module),'-L',str(module),'-lDaBinTestCore','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-module-cache-path',str(stage/'ModuleCache'),str(source),'-o',str(mac/'DaBinReview')],check=True)
shutil.copy2(module/'libDaBinTestCore.dylib',frameworks/'libDaBinTestCore.dylib')
resources_source=stage/'Resources'
if resources_source.exists():
    for name in ('robot.svg','AppIcon.icns'):
        if (resources_source/name).exists():shutil.copy2(resources_source/name,resources/name)
info={'CFBundleIdentifier':f'com.dabin.qa.uxreview.{args.variant}.20260930','CFBundleName':name,'CFBundleDisplayName':name,'CFBundleExecutable':'DaBinReview','CFBundleVersion':'50','CFBundleShortVersionString':'0.4.1','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-',str(frameworks/'libDaBinTestCore.dylib')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
receipt={'application':str(app),'bundleID':info['CFBundleIdentifier'],'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'moduleSHA256':hashlib.sha256((module/'libDaBinTestCore.dylib').read_bytes()).hexdigest(),'archive':('/private/tmp/DaBin-Review-Live-20260930' if args.variant=='baseline' else '/private/tmp/DaBin-Review-Latest-Live-20260930')+'/Archive','safety':'Synthetic root, dedicated preference suite, private pasteboard, fake reminders and screenshot observer, disabled update transport; no production monitors, status item, global shortcuts, or personal archive.'}
(stage/'review-build.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
