#!/bin/bash
# Prepare an archive only. This script never exports, uploads, or submits it.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
python3 scripts/app_store_preflight.py

archive_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_day="$(date -u +%Y-%m-%d)"
archive_root="${DABIN_APP_STORE_ARCHIVE_ROOT:-$HOME/Library/Developer/Xcode/Archives/$archive_day}"
requested_archive_path="${DABIN_APP_STORE_ARCHIVE_PATH:-$archive_root/DaBin-$archive_stamp.xcarchive}"
archive_path="$(python3 scripts/app_store_archive_location.py \
  --destination "$requested_archive_path" --project-root "$project_root")"
archive_root="$(dirname "$archive_path")"
mkdir -p "$archive_root"
# Supply release URLs to this archive without changing the developer's local
# configuration or inventing publicly reachable policy/support destinations.
archive_info="$archive_root/.DaBin-$archive_stamp-Info.plist"
trap 'rm -f "$archive_info"' EXIT
python3 - "$archive_info" <<'PY'
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
  INFOPLIST_FILE="$archive_info" \
  archive
python3 scripts/app_store_preflight.py --app "$archive_path/Products/Applications/DaBin.app"
echo "Archive prepared: $archive_path"
echo "Use Xcode Organizer to validate and distribute with your App Store signing profile. No upload has been performed."
