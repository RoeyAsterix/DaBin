"""Verify the delivered snapshot's checksums; edited files are expected to differ."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'PACKAGE_MANIFEST.json').read_text())
issues = []
for entry in manifest['files']:
    path = (root / entry['path']).resolve()
    if not path.is_relative_to(root):
        issues.append('Unsafe manifest path: ' + entry['path'])
    elif not path.is_file():
        issues.append('Missing: ' + entry['path'])
    elif hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        issues.append('Changed: ' + entry['path'])
print(json.dumps({'files': len(manifest['files']), 'issues': issues}, indent=2))
sys.exit(bool(issues))
