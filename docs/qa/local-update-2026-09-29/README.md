# DaBin 0.4.0 (48) — installed local update

The guarded installer installed **0.4.0, build 48** in the owner's personal Applications folder. The previous application bundle was retained as a backup. Two older running instances were quit normally before replacement; the subsequent launch used only the newly installed application.

This record supersedes the installation blockers in the earlier [work-inbox](../work-inbox-2026-09-29/README.md) and [island playground](../island-playground-2026-09-29/README.md) reports. Those reports retain their original results.

## Archive and preferences

- Before first launch, a private backup preserved both existing archive locations, all **165 files**, and DaBin's preferences under the owner's Library. No archive contents or preference values are included in this repository.
- All 165 files were byte-identical after installation and before the updated app launched.
- A read-only comparison after launch confirmed preservation of all existing fields in **29 capture payloads**, apart from allowed schema metadata, and byte-identical contents for **13 saved attachment originals** across both archives.
- Existing Clipboard, Screenshots, theme, opacity and island-placement preferences were preserved.

The archive backup matters because new saves use schema 7; a backup of the old app bundle alone is insufficient for a rollback to a version that only accepts earlier schemas.

## Installed build verification

- Strict code-signature validation and ARM64 architecture checks passed.
- The installed executable hash and source fingerprint match the [build receipt](build-receipt.json). All **96 recorded build inputs** match the current source files.
- Source fingerprint: `15f87414453c8b3d662c37ad142e1bc0a29b5d41797f492a130cd02406ac6b11`.
- Executable SHA-256: `1a32755364c42c53dd0ed8d8f539e3cfc7bd943ffeb572f45741f7c164319aa5`.
- Live computer-use inspection of the installed Settings screen confirmed **0.4.0 (48)** and the visible **Get updates** controls.

The installed standalone app is locally ad-hoc signed. A passing local signature check does not establish Apple notarization or App Store acceptance.

## Previously unresolved GUI checks

The unlocked-session rerun passed native window focus, Daily capture routing and robot-window transition checks. The header test initially still failed to initialize SwiftUI's virtual accessibility tree. A test-harness-only correction initializes the public accessibility API for its own process before inspection; no assertions were removed and no production behavior was changed for that correction.

| Suite | Final result |
| --- | ---: |
| WindowTests | 223 checks passed |
| DailyCaptureTests | 138 checks passed |
| RobotWindowTransitionTests | 27 checks passed |
| HeaderInteractionTests | 37 checks passed |
| **Previously unresolved suites combined** | **4/4 suites; 425 checks passed** |

Evidence:

- [Initial unlocked rerun](20260929T194516779505Z/report.json): three suites passed; the header accessibility initialization failure remains recorded.
- [Header rerun after harness correction](20260929T194838114542Z/report.json): 37 checks passed.
- [Window log](20260929T194516779505Z/WindowTests.log), [Daily capture log](20260929T194516779505Z/DailyCaptureTests.log), [transition log](20260929T194516779505Z/RobotWindowTransitionTests.log), and [corrected header log](20260929T194838114542Z/HeaderInteractionTests.log).

Both runs recorded unchanged inputs during execution. Their QA fingerprints differ because the header test source changed between runs; the production build inputs remained unchanged. The JSON log paths refer to the original ignored `native/build/qa/runs/` locations; copies are retained alongside each report here.

```sh
bash native/scripts/test.sh --only WindowTests --only DailyCaptureTests \
  --only RobotWindowTransitionTests --only HeaderInteractionTests
# After the header harness correction:
bash native/scripts/test.sh --only HeaderInteractionTests
```

This is a focused rerun of the four outstanding GUI suites, alongside installed-app checks. It is not a new full-suite run or an assertion that every physical drag, notification, display-disconnection or accessibility interaction was exercised. Earlier automated and visual coverage remains in the linked reports.

## Distribution scope

This update installs the local application and prepares the source changes for GitHub. It does not create a public GitHub installer or upload **0.4.0 (48)** to TestFlight. The earlier **0.3.19 (46)** App Store Connect upload is a separate build. Public distribution still requires its own signed and validated artifacts.
