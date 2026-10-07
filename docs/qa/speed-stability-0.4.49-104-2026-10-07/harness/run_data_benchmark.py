import datetime, fcntl, hashlib, json, os, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'speed-data-path'
NATIVE = ROOT / 'snapshot/native'
FREEZE = json.loads((ROOT / 'source-freeze.json').read_text())
CACHE = NATIVE / 'build/qa-cache/app-store-71fe750d8b5b6036f2b1ab71a3e47d509f57e5bea4257d8d5cf65854273791fa'
ENV = {k: v for k, v in os.environ.items() if not k.startswith(('DABIN_', 'DYLD_'))}
ENV['PYTHONDONTWRITEBYTECODE'] = '1'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def snapshot_matches():
    return all((ROOT / 'snapshot' / p).is_file() and sha(ROOT / 'snapshot' / p) == h
               for p, h in FREEZE['fullSnapshotInputs'].items())

def verified_outputs():
    receipt = json.loads((CACHE / 'module-ready.json').read_text())
    if not all(sha(CACHE / name) == value for name, value in receipt['outputs'].items()):
        raise SystemExit('Frozen module output hash mismatch')
    return receipt['outputs']

lock = open('/private/tmp/dabin-speed-stability-qa.lock', 'a+')
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
try:
    if not (ROOT / 'campaign-result.json').is_file():
        raise SystemExit('Main campaign has not completed')
    if not snapshot_matches():
        raise SystemExit('Frozen source inputs changed')
    prep = json.loads((OUT / 'harness-preparation.json').read_text())
    if sha(OUT / 'ReviewPerformance.swift') != prep['harnessSHA256']:
        raise SystemExit('Harness hash mismatch')
    before = verified_outputs()
    flags = ['xcrun', 'swiftc', '-swift-version', '5', '-target', 'arm64-apple-macosx14.0',
             '-module-cache-path', str(OUT / 'ModuleCache'), '-warnings-as-errors',
             '-D', 'REVIEW_DEFERRED_SUPPORT', '-parse-as-library', '-O', '-whole-module-optimization',
             '-I', str(CACHE), '-L', str(CACHE), '-lDaBinTestCore',
             '-Xlinker', '-rpath', '-Xlinker', str(CACHE), str(OUT / 'ReviewPerformance.swift'),
             '-o', str(OUT / 'ReviewPerformance')]
    result = {'startedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'productionFingerprint': FREEZE['productionFingerprint'],
              'harnessSHA256': prep['harnessSHA256'], 'compileArguments': flags,
              'moduleOutputsBefore': before, 'steps': [],
              'scope': 'Synthetic 10,000-record search/save/reopen benchmark; timings are observations with no speed budget.'}
    for name, args, timeout in [('compile', flags, 180),
                               ('run', [str(OUT / 'ReviewPerformance'), str(OUT / 'measurements.json')], 900)]:
        start = time.monotonic()
        with (OUT / (name + '.log')).open('w') as stream:
            process = subprocess.run(args, cwd=NATIVE, env=ENV, stdout=stream,
                                     stderr=subprocess.STDOUT, timeout=timeout)
        result['steps'].append({'stage': name, 'exitCode': process.returncode,
                                'seconds': round(time.monotonic() - start, 3),
                                'logSHA256': sha(OUT / (name + '.log'))})
        if process.returncode:
            break
        if name == 'compile':
            result['executableSHA256BeforeRun'] = sha(OUT / 'ReviewPerformance')
    result['moduleOutputsAfter'] = verified_outputs()
    result['moduleOutputsUnchanged'] = result['moduleOutputsAfter'] == before
    result['snapshotUnchanged'] = snapshot_matches()
    result['finishedAtUTC'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    result['status'] = 'passed' if len(result['steps']) == 2 and all(x['exitCode'] == 0 for x in result['steps']) and result['moduleOutputsUnchanged'] and result['snapshotUnchanged'] else 'failed'
    if (OUT / 'ReviewPerformance').is_file():
        result['executableSHA256AfterRun'] = sha(OUT / 'ReviewPerformance')
    if (OUT / 'measurements.json').is_file():
        result['measurementsSHA256'] = sha(OUT / 'measurements.json')
    (OUT / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    fcntl.flock(lock, fcntl.LOCK_UN)
