# Local signing audit — candidate 2

Observed at 20:46–20:47 UTC on 5 October 2026 with unrestricted, read-only `security` queries. Production fingerprint stayed `165db67e4b9e488b48422b3c4ff56312c00b39dfd226c9a43a597e4c4f449281` before/after. [Identity, public-certificate and profile receipt](verification.json), [profile classification](profile-classification.json), [Xcode/disk prerequisites](archive-prerequisites.json).

| Installed valid identity | Certificate subject OU | SHA-1 | Certificate expiry (UTC) |
|---|---|---|---|
| Apple Development | `8QG4967CSU` | `D71587B10060E08FD5E2312876531CDEE97266B6` | 24 Sep 2027, 15:42:55 |
| Apple Distribution | `8QG4967CSU` | `7A381F9E6466C3E2CA33AD38660334C08FB30232` | 24 Sep 2027, 15:40:12 |
| Developer ID Application | `8QG4967CSU` | `587FFF4ABCE7B751AE3CB11DFC0EBA9666193AC4` | 1 Feb 2027, 22:12:15 |

The Apple Development common-name suffix `PDK64QFH76` is not its team identifier. The actual certificate OU is the configured team. Both `codesigning` and `basic` identity policies list these same three identities. Neither identity policy nor public-certificate searches for “Mac Installer Distribution” / “3rd Party Mac Developer Installer” found an installer identity/certificate.

Exactly one profile was found in the two standard local profile directories:

- Path: `/Users/roeylibfeld/Library/Developer/Xcode/UserData/Provisioning Profiles/d9f1e483-830d-4ab5-90ac-6980c42b64d0.provisionprofile`.
- Name/UUID: `Mac Team Store Provisioning Profile: com.dabin.mac`, `d9f1e483-830d-4ab5-90ac-6980c42b64d0`.
- Platform `OSX`, application identifier `8QG4967CSU.com.dabin.mac`, team `8QG4967CSU`, expires 27 September 2027 at 18:03:32 UTC.
- No device list, all-devices flag or debugger allowance. Repository Store-profile validation returned no violations.
- Contains the installed Apple Distribution certificate `7A381F9E…` and another distribution certificate `8E5B6BB9E48E4AED036132138B9910ED6563F706`, which is not installed as a certificate/valid identity here.
- **Contains no Apple Development certificate. No local development profile was found.**
- **`IsXcodeManaged` is true.** Matching bundle/team/certificate membership does not prove that Xcode will accept this profile under manual signing. No signing-selection attempt was made.

Xcode selection is `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0 (27A266a), macOS SDK 27.0. The project contains no Swift-package reference. `/private/tmp` had approximately 311 GiB available. The shared scheme archives only the app target in Release; XCTest is separately configured for testing.

## Archive choice and blockers

The recommended first local attempt remains the existing automatic development-archive helper, after native QA finishes. A missing development profile alone does not establish an archive blocker for this app's basic sandbox capabilities: the repository's `--archive-app` preflight deliberately allows development archives without distribution app-ID claims or an embedded profile. The correct-team Apple Development identity is installed. Protected private-key use and Xcode's actual asset selection remain untested; the older attempt stopped at Keychain authorization.

```sh
cd '/Users/roeylibfeld/Documents/KARI Creatives/DaBin/native'
export PYTHONDONTWRITEBYTECODE=1
export DABIN_DEVELOPMENT_TEAM=8QG4967CSU
DABIN_LOCAL_ARCHIVE_STAGE="$(mktemp -d /private/tmp/DaBin-Archive-0.4.41-96.XXXXXX)"
export DABIN_APP_STORE_ARCHIVE_PATH="$DABIN_LOCAL_ARCHIVE_STAGE/DaBin-0.4.41-96.xcarchive"
bash scripts/archive_app_store.sh
```

This command is documented, **not executed**. The helper creates a temporary release/fingerprint plist without editing source, uses `CODE_SIGN_STYLE=Automatic`, and checks the resulting development app with `--archive-app`. It has no provisioning-download, export or upload operation. It does **not** forward positional arguments to `xcodebuild`; appending `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY=…` or profile overrides to the helper command does not apply those settings. Its only signing override variable is `DABIN_DEVELOPMENT_TEAM`.

An explicit distribution archive is a separate direct `xcodebuild` experiment, not a helper option and not assured to work with this Xcode-managed profile. If the coordinator elects to try it after inspecting an automatic-signing failure, first create a fresh owned stage and a temporary Store Info.plist exactly as the helper does: current version/build, `DaBinBuildConfiguration=Release`, current `DaBinSourceFingerprint`, and no direct-update channel/feed keys. Then use this command shape with the reviewed temporary plist:

```sh
xcrun xcodebuild -project DaBin.xcodeproj -scheme DaBin -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DABIN_LOCAL_ARCHIVE_STAGE/DerivedData" \
  -archivePath "$DABIN_LOCAL_ARCHIVE_STAGE/DaBin-Store-Signed.xcarchive" \
  -disableAutomaticPackageResolution \
  DEVELOPMENT_TEAM=8QG4967CSU CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=7A381F9E6466C3E2CA33AD38660334C08FB30232 \
  PROVISIONING_PROFILE_SPECIFIER=d9f1e483-830d-4ab5-90ac-6980c42b64d0 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SWIFT_ACTIVE_COMPILATION_CONDITIONS= \
  INFOPLIST_FILE="$DABIN_LOCAL_ARCHIVE_STAGE/Store-Info.plist" archive
python3 -B scripts/app_store_preflight.py \
  --app "$DABIN_LOCAL_ARCHIVE_STAGE/DaBin-Store-Signed.xcarchive/Products/Applications/DaBin.app"
```

Use `--app` for a distribution-signed product: `--archive-app` explicitly accepts Apple Development/Mac Developer authorities only, so it would reject an otherwise correctly distribution-signed archive. Preserve any Xcode-managed-profile incompatibility, signing selection, protected-key or compilation failure. Do not download/create replacement assets, change Keychain access controls, switch to Developer ID signing, or label an unsigned/ad-hoc result as distribution signed.

The missing Mac Installer Distribution identity blocks subsequent signed `.pkg` export. It is not itself a prerequisite to creating an `.xcarchive`. Public-policy parity, owner/contact fields and final signed-runtime acceptance remain independent readiness gates even if local signing succeeds.
