# DaBin App Store review readiness

Updated 6 October 2026 (local); Apple primary-source audit 5 October 2026 UTC. Candidate **0.4.41 (96)**, com.dabin.mac, team `8QG4967CSU`, Apple Silicon, macOS 14 minimum. **DRAFT; submissionReady=false. No upload, submission, Apple account change or public publication performed.**

The full Release Store run completed **125/126 suites**, with unchanged inputs. Zoom performance is the sole failed suite. The unsampled 600.019883-second workload completed without a recorded crash/timeout and also failed the unchanged timing limits. [Authoritative campaign and evidence](../qa/full-review-2026-10-05/README.md).

| Gate | Verified result | Remaining acceptance |
|---|---|---|
| Native functionality |125 functional suites passed; live project/card/note/search/paste/export/companion checks retained |Strict performance unresolved |
| Stability/stress |8,586 durability, 11,674 flow/action, 109,041 graphics, 113 video checks; ten-minute workload completed |p95 input 53.6320 ms and timer 63.0316 ms exceed 50/33 ms; reentrant AppKit warning; no exhaustive leak/energy claim |
| Source/product |Frozen fingerprint d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa; unsigned Store compile/preflight PASS |Final distribution signature, installer and Apple validation |
| XCTest |2/2 PASS, zero failures; exact xcresult metadata and executable hashes |Original collector path error preserved; future collector corrected |
| Sandbox |Fresh-temp ad-hoc fixture save 12/reopen-export 19 checks PASS; ungranted read/write denied; unique container origins verified |Real signed-product grants/bookmarks/install/external transfer, default outgoing temp origin |
| Privacy |39 regressions plus four native light/dark policy renders visually passed; no third-party SDK inventory; declared required reasons source-reviewed |Owner questionnaire confirmation, final signed manifest/entitlements and public-policy parity |
| Signing |Correct-team installed Development/Distribution certificates and valid matching Store profile |No Mac Installer Distribution identity; protected-key use unverified; no archive/package created |
| Cross-app drag |Native gesture plus separate process/file-byte tests passed in fictional fixtures |Physical TextEdit/browser/Finder drop not established; manual receipt explicitly UNTESTED |
| Review assets |Three current-source opaque 1440×900 fictional screenshots, 15-page content DOCX, two-page guide and draft ZIP verified; [artifact receipt](../qa/full-review-2026-10-05/review-pack-final-verification.json) |Final distribution-signed-app screenshot comparison and artwork-rights confirmation |
| Metadata/tooling |90 Python checks passed earlier; unchanged 75 carried forward, affected 15 rerun; current project/static/draft PASS; [final receipt](../qa/full-review-2026-10-05/final-offline/verification.json) |Owner's 11 required fields, privacy/age/encryption/rights/accessibility/trader declarations |
| Local update |[0.4.41 (96) direct Release installed](../qa/full-review-2026-10-05/local-install/verification.json); strict signature and archive-byte preservation verified; previous app backed up |Installed-product launch and final Store signing/runtime still pending |
| Device/OS/manual |ARM64 host 26.6.2, Xcode 27/SDK 27; registered tests use two attached screens |macOS 14/current 27.0.1/another Mac, VoiceOver, physical monitor movement, energy, IPv6 networking, live consent/notifications |
| Public/account |Public policy/support HTTP 200 at recorded 5 October snapshot |Policy is older 4 October text; maintained support/legal/review details, App Store Connect agreements/build availability and Apple review |

The original failed supplemental report and first sandbox signing failure remain retained. Separate current readback/rerun receipts establish XCTest and sandbox PASS without rewriting those failures. Source/test/module hashes stayed unchanged. Ordinary native fixtures, an unsigned app and an ad-hoc sandbox harness do not certify distribution-signed installation or Apple approval.

The owner questions are already pending asynchronously; no duplicate request or invented legal/contact information was added. Archive/export work is held while release acceptance fails and installer identity is absent. No provisioning download, certificate creation, external upload or Apple account operation occurred. The historical local reproduction recipes below are future steps with prerequisites, not evidence that those actions ran. The ordinary full-pass sandbox recipe intentionally rejects the failed overall QA; this campaign's actual separate scoped supplemental receipt is authoritative.

## Applicable Apple requirements

Apple requires a stable, complete app with accurate metadata; a sandboxed, self-contained Mac bundle using Store-managed updates; explicit monitoring consent and visible indication; accessible privacy information; appropriate support; efficient resource use; and current-OS compatibility. Relevant sections are 1.5, 2.1, 2.3, 2.4.2, 2.4.5, 2.5.1, 2.5.5, 2.5.14 and 5.1. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

The privacy-label questionnaire concerns off-device collection, including relevant integrated third-party behavior. Local capture storage is distinct from optional requests for manually saved website previews. The owner must confirm answers for the exact final build. [App privacy details](https://developer.apple.com/app-store/app-privacy-details/). Required-reason APIs must match actual use; the audited reason codes above describe app-only defaults, elapsed event/timer measurement and container file metadata. [Required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

The support URL must provide real contact information; copyright identifies the rights-owning person/entity. [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/). Complete the current [age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/). Trader status needs owner assessment; Apple says a declaration is needed even when not distributing in the EU, with verified public trader contact information when applicable. [Trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

Mac screenshots accept 1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/). Test the minimum supported release and current platform; [macOS 27.0.1 release](https://developer.apple.com/news/releases/?id=09282026c). The April 2026 SDK notice lists iOS/iPadOS/tvOS/visionOS/watchOS SDKs; do not invent a macOS deployment-target requirement from that list. [SDK notice](https://developer.apple.com/news/upcoming-requirements/?id=04282026a). Mac uploads must not contain `com.apple.quarantine`; local preflight already checks this. [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/).

Mac App Store installer packaging uses a Mac Installer Distribution identity. This is distinct from Developer ID distribution/notarization and from Apple Distribution app signing. [Mac packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution?changes=_3). Uploading is a separate workflow and remains excluded. [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Local-only reproduction commands

These commands are a runbook, not evidence that they have run. Run after the coordinator freezes source, one native GUI/QA activity at a time. Keep all files local. Do not add `-allowProvisioningUpdates`, `-allowProvisioningDeviceRegistration`, upload destinations, Transporter/altool upload, notarization, or account operations. Signing may require the user's normal Keychain interaction; do not retrieve passwords or change Keychain access controls. A denied/stalled signer must be reported, not bypassed.

### Source, metadata and independent Python checks

```sh
cd '/Users/roeylibfeld/Documents/KARI Creatives/DaBin/native'
export PYTHONDONTWRITEBYTECODE=1
python3 -B scripts/generate_project.py --check
python3 -B scripts/app_store_preflight.py --static-only
python3 -B -m unittest discover -s Tests -p 'test_*.py'
python3 -B scripts/test_app_store_preflight.py
python3 -B scripts/validate_app_store_metadata.py
python3 -B scripts/validate_app_store_metadata.py --require-complete
```

Strict metadata failure remains expected while legitimate pending gates exist. Do not remove gates or fabricate fields to obtain a pass. The current validator checks presence, not truth, of owner values, and does not validate reachable contact content or Apple approval. Optional `marketingURL` is not a required owner field. Privacy labels, age rating, encryption, rights, accessibility claims, agreements, app record/build availability and applicable business details remain separate checks.

### Test inventory beyond the native suite runner

The read-only [inventory receipt](../qa/full-review-2026-10-05/test-inventory.json) found **126 distinct registered suites and 133 Swift files**, not 121 suites. Seven Swift entry points are outside `run_qa.py`; reporting a full registered run must not imply these also passed. None of the extra entry points below was executed by this inventory audit.

| Unregistered Swift file | Classification and required handling |
|---|---|
| `Tests/XcodeSmokeTests.swift` | **Additional regression:** two XCTest cases for original-byte/day persistence across reopen and same-day search neighbors. Run the Xcode target separately using the isolated command below. |
| `Tests/StoreSandboxSmokeTests.swift` | **Additional Store runtime gate:** run through `Tests/store_sandbox_smoke.py`; this supplies the actual sandbox/signing/container boundary missing from the ordinary runner. Instructions below. |
| `Tests/PrivacyRenderTests.swift` | **Policy-change regression and visual review:** verifies bundled sections/deletion copy, scrollability/bottom reachability and foreground preservation; produces four light/dark PNGs that require inspection. Run `bash scripts/render_privacy_qa.sh` after the correction and after GUI suites finish. |
| `Tests/NativeRenderTests.swift` | **Supplemental render/behavior runner:** snapshots plus some motion/raster assertions, not a missing unit suite. `bash scripts/render_qa.sh --buddy-redesign` uses the early route with injected preferences; `--responsive-detail`, `--open-design`, `--explorer` and `--robot-empty-state` also precede the older standard-preference override. The script compiles the direct channel, so these outputs alone do not verify Store screenshots. |
| `Tests/WalkthroughRenderTests.swift` | **Guide-assets integration/render runner:** verifies its fictional PDF import, extraction/search, comment/task actions, export and reopening while creating tutorial assets. Use `bash scripts/render_walkthrough.sh` when refreshing the guide. It compiles the direct channel and needs its existing `design/walkthrough/assets/Launch-plan.txt` fixture. |
| `Tests/IslandPlaygroundRender.swift` | **Optional motion-preview producer:** renders native frames with movement checks, then encodes/inspects video through `bash scripts/render_island_playground.sh "$DABIN_ISLAND_PREVIEW_OUTPUT"`. Choose a fresh output directory and set `DABIN_FFMPEG` to an existing local executable. It is not application regression or physical frame-rate/energy evidence; no download is needed or implied. |
| `Tests/NativeDropQAMain.swift` | **Manual native-drag fixture:** `bash scripts/build_drop_qa.sh` prepares `/private/tmp/DaBin Drop QA.app`; open that fixture separately for intentional drag interaction and inspect `/private/tmp/DaBinDropQA-results.json`. It creates synthetic text/file sources and a UUID temporary archive without reading the normal archive or clipboard. Its same-process drags do not replace physical Finder/browser acceptance. |

Python discovery under `Tests` is also separate: `test_app_store_archive_location.py`, `test_app_store_metadata.py`, `test_notarized_distribution.py` and `test_qa_distribution.py`. The notarization/distribution tests use fake runners for signing/notarization and temporary packaging fixtures; running those tests does not submit software. Runner-distribution tests mock compilation and native launches. `scripts/test_app_store_preflight.py` is a fifth file outside discovery and must run separately. After metadata/source alignment, run both commands from the earlier section and preserve all results. The earlier 40 passing checks cover only preflight plus archive-location fixtures, not this full Python inventory.

### Separate Xcode smoke target, after source freeze and GUI QA

Set `DABIN_STORE_CANDIDATE` to the absolute fresh unsigned-candidate directory emitted by `build_store_candidate.py`. These two tests use UUID temporary archives. `AppDelegate.applicationDidFinishLaunching` returns when Xcode supplies `XCTestConfigurationFilePath`, so the normal coordinator/services and personal archive/clipboard startup do not run.

Keep XCTest derived data separate: enabling testability or building a test host in the distribution candidate's own derived-data directory can replace the previously receipted app. The Release project does not explicitly enable testability, but the test imports `DaBin` using `@testable`, so the invocation below enables it explicitly. It uses normal per-target plist settings: a global `INFOPLIST_FILE=Store-Info.plist` would also override the generated XCTest bundle's plist. This is a source-matched test host, not proof that the untouched unsigned distribution executable ran these tests.

```sh
: "${DABIN_STORE_CANDIDATE:?Set the absolute fresh Store candidate directory}"
python3 -B - "$DABIN_STORE_CANDIDATE" <<'PY'
import hashlib, json, pathlib, sys
sys.path.insert(0, 'scripts')
from project_inventory import build_inventory, fingerprint
receipt = json.loads((pathlib.Path(sys.argv[1]) / 'store-candidate-receipt.json').read_text())
assert receipt['xcodebuildExitCode'] == 0 and receipt['packagingPreflightExitCode'] == 0
assert receipt['inputsUnchanged'] and receipt['sourceFingerprint'] == fingerprint(build_inventory())
executable = pathlib.Path(receipt['app']) / 'Contents/MacOS/DaBin'
assert hashlib.sha256(executable.read_bytes()).hexdigest() == receipt['executableSHA256']
print('Store candidate matches current source and its executable receipt')
PY
DABIN_XCTEST_STAGE="$(mktemp -d /private/tmp/DaBin-XCTest-0.4.41-96.XXXXXX)"
xcrun xcodebuild \
  -project DaBin.xcodeproj -scheme DaBin -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DABIN_XCTEST_STAGE/derived-data" \
  -resultBundlePath "$DABIN_XCTEST_STAGE/DaBinSmoke.xcresult" \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:DaBinTests/DaBinTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS= ENABLE_TESTABILITY=YES \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO test
```

Record the source fingerprint before/after, candidate executable hash before/after, two test names/results and `.xcresult` path. No signing, provisioning download, upload or normal installed-app launch is requested by this command.

### Fresh local identity and provisioning-profile inspection

Run these read-only commands in the intended local user/keychain context. A restricted tool session can hide otherwise installed identities. The certificate list proves discovery, not successful protected-key use.

```sh
/usr/bin/security find-identity -v -p codesigning
/usr/bin/security find-identity -v -p basic
/usr/bin/xcrun xcodebuild -version
/usr/bin/xcrun --sdk macosx --show-sdk-version
/usr/bin/sw_vers
python3 -B - <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
sys.path.insert(0, 'scripts')
from app_store_preflight import provisioning_profile_violations
signing = json.loads(pathlib.Path('Config/AppStoreSigning.json').read_text())
team, bundle = signing['developmentTeam'], signing['bundleIdentifier']
roots = [pathlib.Path.home() / 'Library/MobileDevice/Provisioning Profiles',
         pathlib.Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles']
matched = 0
for root in roots:
    for path in sorted({*root.glob('*.provisionprofile'), *root.glob('*.mobileprovision')}):
        decoded = subprocess.run(['/usr/bin/security', 'cms', '-D', '-i', str(path)],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if decoded.returncode:
            continue
        try:
            profile = plistlib.loads(decoded.stdout)
        except (ValueError, plistlib.InvalidFileException):
            continue
        app_id = profile.get('Entitlements', {}).get('com.apple.application-identifier')
        if app_id != team + '.' + bundle:
            continue
        matched += 1
        print(json.dumps({'path': str(path), 'uuid': profile.get('UUID'),
            'name': profile.get('Name'), 'expires': str(profile.get('ExpirationDate')),
            'violations': provisioning_profile_violations(profile, team, bundle),
            'allowedCertificateSHA1': [hashlib.sha1(cert).hexdigest().upper()
                for cert in profile.get('DeveloperCertificates', [])]}, indent=2))
print(json.dumps({'matchingLocalProfiles': matched}))
PY
```

Select an unexpired Store profile with no violations and an installed app-signing identity whose SHA-1 appears in that profile. Confirm team from profile claims and certificate subject OU, not the certificate common-name suffix. A Development-signed archive is an intermediate; it does not satisfy the distribution-app check. The missing installer identity must be resolved outside this runbook before export. Do not silently create or download certificates/profiles.

### Unsigned Store Release and enforced-sandbox fixture

```sh
python3 -B scripts/build_store_candidate.py
python3 -B scripts/run_qa.py --distribution app-store --configuration Release
```

The unsigned helper chooses a fresh owned `native/build/store-unsigned-*` directory, records source and project hashes, checks unchanged inputs, and writes `store-candidate-receipt.json`. Its Xcode command disables signing and automatic package resolution and has no archive/export/upload operation. Inspect that receipt and `unsigned-packaging-preflight.log`; success alone does not authorize or prove launch under App Sandbox.

Use the exact successful full Store QA report emitted above to resolve its module, rather than choosing an arbitrary older cache. Set `DABIN_STORE_QA_REPORT` to that report's absolute path. This check is read-only and rejects changed inputs or partial QA.

```sh
: "${DABIN_STORE_QA_REPORT:?Set the absolute path of the final full Store QA report}"
export DABIN_STORE_QA_REPORT
DABIN_STORE_MODULE="$(python3 -B - <<'PY'
import hashlib, json, os, pathlib, sys
sys.path.insert(0, 'scripts')
import run_qa as qa
from project_inventory import ROOT, sources, hashes, fingerprint
report = json.loads(pathlib.Path(os.environ['DABIN_STORE_QA_REPORT']).read_text())
assert report['status'] == 'passed' and not report['sourceChangedDuringRun']
assert report['coverage'] == 'full_registered_suite'
assert report['distribution'] == 'app-store' and report['configuration'] == 'Release'
selected = [suite['name'] for suite in report['suites'] if suite['status'] != 'not_requested']
assert report['inputs'] == qa.input_snapshot(selected), 'QA inputs have changed'
inputs = {'sources': hashes(sources(False)), 'compiler': report['swiftVersion'],
    'sdk': report['sdkVersion'], 'target': report['target'], 'configuration': 'Release',
    'distribution': 'app-store', 'compileDefinitions': report['compileDefinitions'],
    'runner': hashlib.sha256((ROOT / 'scripts/run_qa.py').read_bytes()).hexdigest(),
    'inventory': hashlib.sha256((ROOT / 'scripts/project_inventory.py').read_bytes()).hexdigest()}
module = ROOT / 'build/qa-cache' / ('app-store-' + fingerprint(inputs))
assert json.loads((module / 'module-ready.json').read_text())['inputs'] == inputs
print(module)
PY
)"
python3 -B Tests/store_sandbox_smoke.py --module-dir "$DABIN_STORE_MODULE" --run
```

The fixture locally compiles and ad-hoc signs a separate unique app, then launches it twice headlessly. It uses fictional data and a deliberately ungranted file; it does not operate the personal archive, clipboard, production app, network or permission panels. Its stricter sandbox verifies actual denial and persistence, but not distribution signing, all production entitlements, real picker/bookmark consent or installation. A host/tool outer-sandbox launch failure must remain recorded; running that fixture outside the tool wrapper is not the same as disabling its own App Sandbox.

### Local development archive

Proceed only after current QA and source freeze, with matching installed signing assets. The helper validates that the fresh destination is outside the repository and File Provider locations; it does not replace an existing archive. [Fresh asset audit and exact signing caveats](../qa/full-review-2026-10-05/local-signing-assets-candidate2/README.md): the Apple Development identity has the correct team OU; no Development profile was found, but the archive preflight permits these basic development archives without one. The only installed Store profile is Xcode-managed. The helper hardcodes automatic signing and ignores extra positional Xcode arguments.

```sh
DABIN_STORE_STAGE="$(mktemp -d /private/tmp/DaBin-Store-0.4.41-96.XXXXXX)"
export DABIN_STORE_STAGE
export DABIN_APP_STORE_ARCHIVE_PATH="$DABIN_STORE_STAGE/DaBin-0.4.41-96.xcarchive"
bash scripts/archive_app_store.sh
python3 -B scripts/app_store_preflight.py \
  --archive-app "$DABIN_APP_STORE_ARCHIVE_PATH/Products/Applications/DaBin.app"
```

The helper embeds a source fingerprint and Release marker without editing source Info.plist, compiles the Xcode Store target, and checks the archive app. Confirm its receipt/log against frozen inputs. It may require normal Keychain authorization; no archive is valid merely because compilation reached signing. Save the final archive path before ending the shell session.

### Local distribution export — blocked until installer identity exists

Set these variables from the fresh local identity/profile inspection: `DABIN_STORE_APP_CERT_SHA1` (Apple Distribution/Store application identity), `DABIN_STORE_INSTALLER_CERT_SHA1` (Mac Installer Distribution identity), and `DABIN_STORE_PROFILE_PATH` (matching local Store profile). Never copy the October 4 historical selections without verification. Keep the stage/archive variables from the completed archive command.

```sh
: "${DABIN_STORE_STAGE:?Use the owned stage from the completed archive}"
: "${DABIN_APP_STORE_ARCHIVE_PATH:?Use the verified completed archive path}"
: "${DABIN_STORE_APP_CERT_SHA1:?Select a current installed Store app-signing identity}"
: "${DABIN_STORE_INSTALLER_CERT_SHA1:?Select a current installed Mac Installer Distribution identity}"
: "${DABIN_STORE_PROFILE_PATH:?Select the current matching local Store profile}"
export DABIN_STORE_APP_CERT_SHA1 DABIN_STORE_INSTALLER_CERT_SHA1 DABIN_STORE_PROFILE_PATH
python3 -B - <<'PY'
import hashlib, json, os, pathlib, plistlib, re, subprocess, sys
sys.path.insert(0, 'scripts')
from app_store_preflight import provisioning_profile_violations
signing = json.loads(pathlib.Path('Config/AppStoreSigning.json').read_text())
team, bundle = signing['developmentTeam'], signing['bundleIdentifier']
app_cert = os.environ['DABIN_STORE_APP_CERT_SHA1'].upper()
installer_cert = os.environ['DABIN_STORE_INSTALLER_CERT_SHA1'].upper()
assert re.fullmatch(r'[A-F0-9]{40}', app_cert) and re.fullmatch(r'[A-F0-9]{40}', installer_cert)
identities = subprocess.check_output(['/usr/bin/security', 'find-identity', '-v', '-p', 'basic'], text=True)
app_line = next((line for line in identities.splitlines() if app_cert in line), '')
installer_line = next((line for line in identities.splitlines() if installer_cert in line), '')
assert 'Apple Distribution:' in app_line or '3rd Party Mac Developer Application:' in app_line
assert 'Mac Installer Distribution:' in installer_line or '3rd Party Mac Developer Installer:' in installer_line
data = subprocess.check_output(['/usr/bin/security', 'cms', '-D', '-i', os.environ['DABIN_STORE_PROFILE_PATH']])
profile = plistlib.loads(data)
assert not provisioning_profile_violations(profile, team, bundle)
assert app_cert in {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
options = {'destination': 'export', 'method': 'app-store-connect', 'signingStyle': 'manual',
    'teamID': team, 'signingCertificate': app_cert, 'installerSigningCertificate': installer_cert,
    'provisioningProfiles': {bundle: profile['UUID']}, 'manageAppVersionAndBuildNumber': False,
    'generateAppStoreInformation': False, 'uploadSymbols': False}
path = pathlib.Path(os.environ['DABIN_STORE_STAGE']) / 'ExportOptions-LOCAL-ONLY.plist'
with path.open('xb') as stream:
    plistlib.dump(options, stream)
print(path)
PY
xcrun xcodebuild -exportArchive \
  -archivePath "$DABIN_APP_STORE_ARCHIVE_PATH" \
  -exportPath "$DABIN_STORE_STAGE/export" \
  -exportOptionsPlist "$DABIN_STORE_STAGE/ExportOptions-LOCAL-ONLY.plist"
```

Inspect the exact exported products locally. Run `pkgutil --check-signature` on the emitted package. If the export includes a `.app`, run `python3 -B scripts/app_store_preflight.py --app` on it; otherwise expand the package into a fresh owned inspection directory using `pkgutil --expand-full` and inspect its app there. Do not install the package as an inspection shortcut or mistake the development app inside the original archive for the exported distribution-signed app. Record architecture, version/build, production fingerprint, exact resources, signature, entitlements, Store profile/certificate membership, absence of direct updater/helper, and absence of quarantine attributes. Local preflight is not Apple's server-side validation or review.

## Manual acceptance that automated receipts do not replace

Use a fictional archive and a separate test account/container where possible. Record which exact signed app was used and preserve the personal application/archive.

- Fresh launch, relaunch, clean installation and upgrade with original capture bytes and local drafts retained; save-failure behavior and safe quit during active work.
- Manual paste/import, incoming/outgoing Finder and browser drops, native export/save pickers, chosen-folder bookmark restoration and revocation.
- Clipboard/screenshots independently off by default, explicit consent, baseline exclusion, Pause/Off behavior, no automatic-link preview requests, visible recording state with board closed and Quiet mode on.
- Notification consent/denial and generic reminder content; timer alarm dismissal; companion first-peek/retreat single-click, camera exclusions, display changes and paused Unfiled/project status.
- Keyboard navigation, VoiceOver, reduced motion/transparency and contrast; use Apple's criteria before making Accessibility Nutrition Label claims.
- Idle and realistic capture/preview/OCR load with measured CPU, memory, disk writes and responsiveness; document duration and fixture volume. Passing bounded stress tests is not an indefinite soak, exhaustive heap-leak audit, physical frame-rate measurement or battery-energy certification.
- Minimum macOS 14 and current macOS 27.0.1; available notch/non-notch/external display coverage; optional website previews offline and on IPv6-only networking.
- Final fictional screenshots, support contact adequacy, published/bundled policy parity and owner declarations. External publication, Apple account changes, upload and submission remain outside this task.
