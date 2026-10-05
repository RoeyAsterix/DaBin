"""Run from the signed-in Mac Terminal; uses normal installed signing assets."""
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path('/Users/roeylibfeld/Documents/KARI Creatives/DaBin/native')
expected = 'dae2228aa8ea9dcd4e3dd556ccc8aeb7273e230b1471340feb3eebb1fa2cc8a1'
code_commit = 'b89e73d2e27907d3677f3478a56e067c58fdcd89'
os.chdir(root)
sys.path.insert(0, str(root / 'scripts'))
from project_inventory import build_inventory, fingerprint, hashes
extra_inputs = {'Config/AppStoreSigning.json': 'a6072c1ad444175cf204f71d3f8d8d39e0d15bcd3d74d672a4a1924ac525ddf5', 'DaBin.xcodeproj/project.pbxproj': '271ac8dbec9ca5b278ae8ea42ba42367744953a5963054333c6d6debe6aa85d3', 'DaBin.xcodeproj/xcshareddata/xcschemes/DaBin.xcscheme': '0922aad38e86918dc38f90b76d197e0405997d7dcd571bde62063ae96e4db283'}
assert hashes([root / name for name in extra_inputs]) == extra_inputs, 'Build configuration changed; request a current handoff'
assert fingerprint(build_inventory()) == expected, 'Source changed; request a current handoff'
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == '0.4.33' and str(info['CFBundleVersion']) == '88'
assert info['CFBundleIdentifier'] == 'com.dabin.mac'
subprocess.run(['git', 'merge-base', '--is-ancestor', code_commit, 'HEAD'], cwd=root.parent, check=True)
lock = open('/private/tmp/dabin-testflight-current-archive.lock', 'a')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit('Another current human archive is running; do not overlap it')
now = datetime.datetime.now(datetime.timezone.utc)
stamp = now.strftime('%Y%m%dT%H%M%SZ')
archive = Path.home() / 'Library/Developer/Xcode/Archives' / now.strftime('%Y-%m-%d') / f'DaBin-0.4.33-88-TestFlight-remove-organize-pin-interactive-{stamp}.xcarchive'
log = Path(f'/private/tmp/dabin-testflight-remove-organize-pin-interactive-{stamp}.log')
receipt = Path(f'/private/tmp/dabin-testflight-remove-organize-pin-interactive-{stamp}-receipt.json')
environment = os.environ.copy()
environment['PATH'] = str(Path(sys.executable).parent) + ':' + environment['PATH']
environment['DABIN_APP_STORE_ARCHIVE_PATH'] = str(archive)
record = dict(status='running_in_human_terminal', sourceFingerprint=expected, codeCommit=code_commit,
              version='0.4.33', build='88', bundleIdentifier='com.dabin.mac', archivePath=str(archive),
              logPath=str(log), startedAtUTC=now.isoformat(), runnerPID=os.getpid(), signed=False, uploaded=False)
def save():
    receipt.write_text(json.dumps(record, indent=2) + '\n')
with log.open('wb') as output:
    process = subprocess.Popen(['bash', 'scripts/archive_app_store.sh'], env=environment, stdout=output, stderr=subprocess.STDOUT)
    record['helperPID'] = process.pid
    save()
    print('Archive started. Complete any normal macOS signing prompt on this Mac.', flush=True)
    print('Log: ' + str(log), flush=True)
    print('Receipt: ' + str(receipt), flush=True)
    try:
        result = process.wait()
    except KeyboardInterrupt:
        record.update(status='human_interrupted', signed=False)
        save()
        raise
unchanged = fingerprint(build_inventory()) == expected and hashes([root / name for name in extra_inputs]) == extra_inputs
record.update(exitCode=result, inputsUnchanged=unchanged,
              status='archive_completed' if result == 0 and unchanged else 'archive_failed_or_source_changed',
              signed=result == 0 and unchanged, finishedAtUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              logSHA256=hashlib.sha256(log.read_bytes()).hexdigest())
save()
print('Result: ' + record['status'], flush=True)
print('No upload performed. Return to Codex for archive verification and TestFlight upload.', flush=True)
sys.exit(0 if result == 0 and unchanged else 1)
