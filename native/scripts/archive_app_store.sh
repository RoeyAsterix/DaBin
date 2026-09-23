#!/bin/bash
# Prepare an archive only. This script never exports, uploads, or submits it.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
python3 scripts/app_store_preflight.py

archive_root="$project_root/build/app-store"
archive_path="$archive_root/DaBin.xcarchive"
if [ -e "$archive_path" ]; then
  echo "An archive already exists at $archive_path. Preserve or move it before creating another archive."
  exit 1
fi
mkdir -p "$archive_root"
# Supply release URLs to this archive without changing the developer's local
# configuration or inventing publicly reachable policy/support destinations.
python3 - "$archive_root/Info.plist" <<'PY'
import os, pathlib, plistlib, sys
sys.path.insert(0, 'scripts')
from project_inventory import build_inventory, fingerprint
source = pathlib.Path('Resources/Info.plist')
info = plistlib.loads(source.read_bytes())
info['DaBinBuildConfiguration'] = 'Release'
info['DaBinSourceFingerprint'] = fingerprint(build_inventory())
info.pop('DaBinUpdateManifestURL', None)
info.pop('DaBinDistributionChannel', None)
for environment_key, plist_key in [('DABIN_PRIVACY_POLICY_URL', 'DaBinPrivacyPolicyURL'),
                                   ('DABIN_SUPPORT_URL', 'DaBinSupportURL')]:
    info[plist_key] = os.environ.get(environment_key, info.get(plist_key, ''))
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
xcrun xcodebuild \
  -project DaBin.xcodeproj -scheme DaBin -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$DABIN_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  INFOPLIST_FILE="$archive_root/Info.plist" \
  archive
echo "Archive prepared: $archive_path"
echo "Use Xcode Organizer to validate and distribute with your App Store signing profile. No upload has been performed."
