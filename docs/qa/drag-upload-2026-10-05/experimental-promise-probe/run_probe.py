import hashlib
import json
from pathlib import Path
import subprocess
import time

root = Path('/private/tmp/dabin-native-file-promise-probe-20261005')
cases = [
    ('direct-plain', ['--release']),
    ('direct-coordinated', ['--release']),
    ('wrapped-plain', ['--release']),
    ('wrapped-coordinated', ['--release']),
    ('wrapped-plain', ['--routed']),
    ('wrapped-coordinated', ['--routed']),
]
results = []
for name, flags in cases:
    case = name + ('-released' if '--release' in flags else '-retained') + ('-routed' if '--routed' in flags else '')
    started = time.monotonic()
    try:
        process = subprocess.run([str(root / 'NativePromiseProbe'), name] + flags, cwd=root,
            capture_output=True, text=True, timeout=18)
        output = process.stdout + process.stderr
        result = {'case': case, 'exitCode': process.returncode,
            'elapsedSeconds': time.monotonic() - started, 'explicitComplete': 'COMPLETE: result=' in output}
    except subprocess.TimeoutExpired as error:
        output = ((error.stdout or b'').decode() if isinstance(error.stdout, bytes) else (error.stdout or ''))
        output += ((error.stderr or b'').decode() if isinstance(error.stderr, bytes) else (error.stderr or ''))
        result = {'case': case, 'timedOut': True, 'elapsedSeconds': time.monotonic() - started,
            'explicitComplete': False}
    (root / (case + '.log')).write_text(output)
    results.append(result)
    print(json.dumps(result), flush=True)
manifest = {'probeSourceSHA256': hashlib.sha256((root / 'NativePromiseProbe.swift').read_bytes()).hexdigest(),
    'executableSHA256': hashlib.sha256((root / 'NativePromiseProbe').read_bytes()).hexdigest(),
    'cases': results, 'repositoryImports': False, 'windowCount': 0, 'generalClipboardUsed': False}
(root / 'run-results.json').write_text(json.dumps(manifest, indent=2) + '\n')
