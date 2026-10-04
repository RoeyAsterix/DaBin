#!/usr/bin/env python3
"""Reproduce local DaBin fixture assets from the existing hash-verified native QA module.
This opens only isolated nonactivating offscreen windows and never the live app.
"""
from pathlib import Path
import hashlib, json, subprocess
HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
NATIVE=REPO/'native/build/store-preparation-20261004/native'
CACHE=NATIVE/'build/qa-cache/app-store-34dd658724d8a131934a15dd329a81843c7c8c7af3aad201a34ea2bf28acde4a'
EXPECTED={'DaBinTestCore.swiftmodule':'687c1551740c2dcec8ac85f9c05b779aa77feba3ce04d5cbab0d2ab6325d9255','libDaBinTestCore.dylib':'45ed376eb743afff149ce09e96706221784da98ed7290a4454131a3c60e9f2f8'}
for name,sha in EXPECTED.items():
    p=CACHE/name
    if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:
        raise SystemExit('Frozen 0.4.31 (86) production QA module missing or changed. Preserve these source images; review the new release before rebuilding.')
BUILD=HERE/'.build';BUILD.mkdir(exist_ok=True)
command=['xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-module-cache-path',str(BUILD/'ModuleCache'),'-warnings-as-errors','-O','-parse-as-library','-I',str(CACHE),'-L',str(CACHE),'-lDaBinTestCore','-Xlinker','-rpath','-Xlinker',str(CACHE),str(HERE/'RenderMarketingAssets.swift'),'-o',str(BUILD/'RenderMarketingAssets')]
subprocess.run(command,check=True)
subprocess.run([str(BUILD/'RenderMarketingAssets'),str(HERE)],check=True,timeout=90)
print('Native sources recreated. Next run GenerateGraphics.py with the bundled Python/Pillow runtime.')
