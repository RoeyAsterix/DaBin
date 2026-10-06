# DaBin App Store readiness — 5 October 2026

Expected candidate: **0.4.41 (96)**, bundle ID `com.dabin.mac`, team `8QG4967CSU`, Apple Silicon, macOS 14 or later. This is a local preparation record. The expected version is a target until the final receipts below confirm it. **No upload, submission, public release, policy publication, or Apple account change is authorized by this work.**

Draft status updated **2026-10-05T22:10:43Z** (6 October locally in Asia/Jerusalem). The locked source passed three focused functional suites, then **125/126 full Store suites** with unchanged inputs. The sole failed suite is zoom performance, and the subsequent **600.019883-second unsampled workload also failed its strict timing gate**. Overall QA remains **FAILED**; remaining supplemental/distribution acceptance is pending. [Campaign evidence and retained failures](../qa/full-review-2026-10-05/README.md).

## Evidence and remaining gates

| Gate | Current evidence | Status for 0.4.41 (96) |
|---|---|---|
| Source and candidate identity | [Locked source](../qa/full-review-2026-10-05/final-candidate/source-freeze.json) is 0.4.41 (96), frozen at `2026-10-05T21:30:22.135740Z`, production fingerprint `d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa`. The focused direct and full Store reports confirm unchanged run inputs. Candidate 1 tooling, candidate 2 signing observations and earlier failed native attempts retain their own provenance. | **SOURCE LOCKED; FUNCTIONAL SUITES PASSED:** overall Store QA failed only performance; Store product and executable acceptance remain pending |
| Full native Release QA | The retained [direct baseline](../qa/full-review-2026-10-05/baseline-direct/report.json) failed at 125/126 on 0.4.40 (95). The locked source's [direct focused run](../qa/full-review-2026-10-05/final-candidate/focused-functional-report.json) passed 3/3 (918/782/38 checks). The [full Store report](../qa/full-review-2026-10-05/final-store/full-qa-report.json) then passed **125/126**, from `2026-10-05T21:33:52.249116Z` to `2026-10-05T21:58:07.618739Z`, with unchanged inputs. Only `WorkspaceZoomPerformanceTests` failed. Store ProjectWorkspaceView reported **917**, card **782**, drag **38**, privacy **39**, SearchInput **65** and video **113** passing checks. Native executables do not enforce distribution sandbox/signing or establish installation/physical cross-app acceptance. | **FULL STORE FAILED, 125/126:** 125 functional suites passed; performance remains a blocker, not a waived or pending result |
| Stability and stress | Final Store durability passed **8,586** checks (1,000 seeded records, 320 operations, 25 reopen comparisons, four fixture-process SIGKILL boundaries); semantic flow/action passed **11,674** and seeded graphics/animation/disposal passed **109,041**. The [30-second workload](../qa/full-review-2026-10-05/final-store/zoom-performance/performance.json) failed **51.3154/61.2394 ms** against unchanged **50/33 ms** gates. The [unsampled sustained workload](../qa/full-review-2026-10-05/final-supplement/sustained-readback.json) completed **600.019883 measured seconds**, 5,000 + 399 = **5,399 captures**, 160 input samples, five cycles, 2,000 originals and 1,000 thumbnails; **53.6320/63.0316 ms** still failed. No crash/timeout was recorded, but no total assertion count was emitted before the timing failure. | **BOUNDED FUNCTIONAL STRESS PASSED; BOTH PERFORMANCE RUNS FAILED:** sustained means five cycles spread across ten minutes with burst/arrivals and idle, not continuous zoom. Max RSS 251,412,480 bytes and whole-process CPU 6.7420% are observations, not leak/energy certification; retain the unresolved AppKit reentrant-delegate warning. |
| Offline preparation regressions | Candidate 1 passed all **90 Python tests** (58 discovery plus 32 preflight), generated-project consistency and static Store preflight; [receipt and logs](../qa/full-review-2026-10-05/candidate1-python/verification.json). Production and separately inventoried test/script/config/project/metadata hashes remained unchanged. The earlier 40-check audit is also preserved byte-for-byte in [packaging-regressions](../qa/full-review-2026-10-05/packaging-regressions/verification.json). | **PASS for frozen candidate 1 tooling;** rerun affected checks if relevant inputs change |
| Metadata | Candidate 1 passed the draft validator's copy limits, version/build alignment, no-account notes and policy URL alignment. [Strict validation](../qa/full-review-2026-10-05/candidate1-python/metadata-strict.log) correctly failed on 11 unresolved owner fields plus pending external gates; `submissionReady` remains false. | **LOCAL DRAFT PASS; SUBMISSION INCOMPLETE:** truthful owner fields and external gates remain pending |
| Permissions and privacy manifest | Source inspection found four scoped entitlements: sandbox, user-selected read/write, app-scoped bookmarks and outbound networking. Manifest declares no tracking/collected data and reasons CA92.1, 35F9.1 and C617.1. The [timestamp origin audit](../qa/full-review-2026-10-05/required-reason-source-audit.md), checked `2026-10-05T22:06:18.489211Z`, traces actual date/stat reads to managed originals/previews/daily files and the default app temporary outgoing root; 25 recorded hashes match the locked source. External imports/screenshots/backup paths inspect other metadata without a concrete timestamp API path. No additional reason is recommended. | **SOURCE REVIEW COMPLETE;** sandbox runtime must still confirm actual container/temp resolution; inspect final bundled manifest, signed entitlements and runtime behavior. Custom external root injections are tests, not shipping-origin evidence. |
| Policy and in-app copy | The revised local policy is dated October 5 and now describes clickable kind/count confirmations, static Quiet mode/Reduce Motion behavior, and persistent project/Paused/Unfiled labels with project-name visibility disclosure. The coordinator also corrected the Quiet mode subtitle and privacy regression expectation. Final Store `PrivacyInformationTests` passed **39 checks**; separate policy render inspection and final bundled/submission copies remain unverified. | **SOURCE/REGISTERED REGRESSION PASS; FINAL GATE PENDING:** rendered policy inspection, bundled/pack copy and eventual public parity; do not publish during this task |
| Public links | At 20:15:10 UTC on October 5, unauthenticated GETs returned HTTP 200 for the configured GitHub policy page, raw policy markdown and Issues support page. That October 4 public snapshot matched the then-current local copy. It now differs from the revised October 5 local policy: [local-only comparison and hashes](../qa/full-review-2026-10-05/policy-parity-after-correction/verification.json), [wording diff](../qa/full-review-2026-10-05/policy-parity-after-correction/public-to-local.diff). The original [HTTP receipt](../qa/full-review-2026-10-05/public-links-20261005T201510941646Z/verification.json) and [public text](../qa/full-review-2026-10-05/public-links-20261005T201510941646Z/public-policy.md) are preserved unchanged. No fresh fetch or publication was performed after the correction. | **KNOWN SNAPSHOT MISMATCH; FINAL PARITY PENDING:** publish only in a separately authorized task, then verify the final public policy. HTTP 200 does not establish adequate owner contact. |
| Store compile and packaging | `build_store_candidate.py` builds a separate unsigned Xcode Store Release product, clears direct-update definitions, records input hashes and runs unsigned packaging preflight. | **PENDING:** exact-candidate build/preflight receipt; unsigned success is not signing or sandbox-runtime evidence |
| Enforced sandbox | Ordinary native QA executables are not distribution-signed and do not enforce the app's sandbox entitlements. The separate sandbox fixture uses a unique app/container and tests actual denied access and saved-data reopening. Historical October 4 smoke is for an older module. | **PENDING:** current Store-module smoke and final signed-app grant/persistence tests |
| Signing assets | The [fresh unrestricted audit](../qa/full-review-2026-10-05/local-signing-assets-candidate2/README.md) confirms all three installed identities have certificate subject OU `8QG4967CSU`, including Apple Development despite its different common-name suffix. The installed, unexpired `com.dabin.mac` Store profile contains the installed Apple Distribution certificate and passes local profile checks. No development profile or Mac Installer Distribution identity/certificate was found. The Store profile is explicitly Xcode-managed. | **BLOCKED for installer export:** required installer identity is missing. App certificate/profile membership is verified; protected-key use and Xcode signing selection remain pending. |
| Archive/export | The helper hardcodes automatic development signing and does not forward positional Xcode overrides. A development archive may use the installed correct-team identity without an embedded profile for these basic capabilities; `--archive-app` permits that. The October 4 attempt stopped at protected Keychain authorization. An explicit distribution archive would need a direct command and `--app` validation; manual selection of the Xcode-managed Store profile is unverified. | **PENDING:** fresh local archive attempt after QA; installer export blocked as above; no Apple validation/upload |
| Supported OS | Read-only local check: macOS 26.6.2, Xcode 27.0 (27A266a), SDK 27.0. Apple lists macOS 27.0.1 as released on September 28. | **PENDING:** minimum macOS 14 and current macOS 27.0.1 runtime acceptance |
| Screenshots and guide | Existing submission pack and three fictional native 1440 × 900 screenshots target 0.4.31 (86). | **PENDING:** refresh or compare against final candidate, inspect at full size, verify opaque output and artwork rights |
| Owner and Connect information | Public support/contact, rights holder, private review contacts, pricing, territories, release method and trader status are unresolved locally. No Connect record or agreements were inspected. | **PENDING OWNER/EXTERNAL:** complete truthful information later; keep private review contact details out of public source |
| Final real-app acceptance | Source/module tests cannot establish native picker/bookmark grants, real notification consent, physical external drops, signed install/upgrade, full VoiceOver usability, IPv6-only networking or long-running energy behavior. | **PENDING:** record each separately; never infer these from a passing unit/render suite |

### Final coordinated evidence — to be completed by the coordinator

- Final source version/build and production fingerprint: **LOCKED** at 0.4.41 (96), `2026-10-05T21:30:22.135740Z`, `d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa`. Broader acceptance remains pending; intermediate receipts keep their earlier fingerprints.
- Frozen input manifest and unchanged-input result: the [locked-source direct focused report](../qa/full-review-2026-10-05/final-candidate/focused-functional-report.json) passed 3/3 with QA input fingerprint `2597c1bfe134be3c39f19b5d2409a0c09126e4a3d57c05940c9ff3b8f21b758e`. The [full Store report](../qa/full-review-2026-10-05/final-store/full-qa-report.json) completed 125/126 with QA input fingerprint `2aeea5999079e497250affa175b7cd50a75c418fd243920679e567cb69ac2029`. Both report unchanged inputs; these QA inventories are distinct from the production fingerprint. Earlier Python/static checks retain their [candidate 1 receipt](../qa/full-review-2026-10-05/candidate1-python/verification.json).
- Direct Release QA scope, retained failures and reruns: **LOCKED-SOURCE FOCUSED 3/3 PASS** (918/782/38 checks). The [0.4.40 (95) full baseline](../qa/full-review-2026-10-05/baseline-direct/report.json) remains failed at 125/126. No full direct pass or performance acceptance is inferred from the focused run.
- Full Store Release QA report, passed/registered suites, retained failures and reruns: **FAILED, 125/126**, `2026-10-05T21:33:52.249116Z`–`2026-10-05T21:58:07.618739Z`, only `WorkspaceZoomPerformanceTests` failed; [retained report](../qa/full-review-2026-10-05/final-store/full-qa-report.json), SHA-256 `5d8c0dec20236f0de08803694224ca4b75dda00c0e330248b2f7311e426fa0eb`.
- Separate Xcode XCTest target result bundle (two tests, isolated test host): **PENDING**.
- Stability/stress reports, duration, fixture counts, CPU/memory/disk observations and limits: final Store bounded durability/flow/graphics checks **PASSED** as above. Both [30-second](../qa/full-review-2026-10-05/final-store/zoom-performance/performance.json) and [600.019883-second unsampled](../qa/full-review-2026-10-05/final-supplement/sustained/wrapper-report.json) workloads **FAILED unchanged 50/33 ms gates**. Sustained coordinator phase: `2026-10-05T21:59:35.121102Z`–`2026-10-05T22:09:39.751371Z`; source/module unchanged, completed with exit 1 at the timing assertion, sampling disabled. Five spread-out cycles and 5,399 final captures; no independent disk/energy/leak certification.
- Metadata/preflight/Python results and persistent copies of audit logs: **PASS for candidate 1's 90 Python tests, project consistency, static preflight and draft metadata**; [receipt](../qa/full-review-2026-10-05/candidate1-python/verification.json). Strict metadata retains its expected owner/external-gate failure.
- Unsigned Store build receipt, executable SHA-256 and packaging preflight: **PENDING**.
- Current enforced-sandbox smoke receipt: **PENDING**.
- Development archive path, signing/entitlement inspection and fingerprint: **PENDING**.
- Distribution app/package, signer/profile checks and package signature: **BLOCKED: installer signing identity missing**.
- Final screenshot/guide manifest and visual comparison: **PENDING**.
- Real signed-app acceptance and remaining OS/hardware/accessibility/network gaps: **PENDING**.
- Public support adequacy and final published policy parity: **PENDING**. The [preserved October 4 public snapshot differs from the revised October 5 local copy](../qa/full-review-2026-10-05/policy-parity-after-correction/verification.json). Public URLs returned HTTP 200 at the earlier observation; no refetch or publication followed the correction.
- Upload/submission/account changes: **NOT PERFORMED; outside this task**.

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
