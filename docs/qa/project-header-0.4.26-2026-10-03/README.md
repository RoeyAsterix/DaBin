# Project header cleanup — 0.4.26 (81)

The project name now appears only in the main dropdown, with an unfiltered item count beneath it. The duplicate folder/name row and “One place for your project” tagline are removed. Search, the existing single Export action, and the Project actions menu share one compact toolbar.

## Verification

Five focused Release suites pass, **921 checks**, with no source changes during the final run:

- ProjectPickerTests: 23.
- ProjectWorkspaceStateTests: 253, including 17 new count/membership assertions.
- ProjectWorkspaceViewTests: 185, including absence of the duplicate heading/tagline, responsive bulk actions, and a 1,002-item synthetic project. At most 25 native rows materialized.
- HeaderInteractionTests: 219.
- WorkspaceWindowTests: 241, including whole-project count under filtering, notes-only singular count, live capture insertion/reassignment, and long project names.

The initial run passed four suites and exposed a stale Search test expectation: the test measured a launch-search button that the existing active Search screen intentionally hides. Only that test was corrected, adding an explicit absence assertion; production Search behavior was preserved. The final five-suite rerun passes. The initial failure is retained separately.

Native render fixtures were visually reviewed at 380 and 1,280 points, and for a long notes-only project at 380 points. The standalone 320-point project grid retains the Export label and actions menu. Tests use fictional temporary archives, not personal captures or the real clipboard. This is focused UI regression testing, not a full-suite, minimum-OS, or App Store validation.

Raw final run: `native/build/qa/runs/20261003T160303879864Z/report.json`. Source inventory and hashes are preserved in the copied report. Generated Xcode project check and `git diff --check` pass.

## Local installation

The Release ARM64 build is installed and running at `/Users/roeylibfeld/Applications/DaBin.app`. Normal quit preceded the guarded installation. The previous bundle is recoverable at `/Users/roeylibfeld/Applications/.DaBinBackups/20261003-190618-2fd36328.app`.

- Installed version/build: **0.4.26 (81)**.
- Source fingerprint: `f01f64268576724968417eec151d74632ba743b0f31f2bc1c290442575a07ba8`.
- Installed executable SHA-256 matches the build receipt: `b6ae71f19bef3cce2f52546da2e18e36b959caafb33aa6462adb12459bf1bdfa`.
- Strict deep signature verification passes.
- Live accessibility confirms the selected project appears in the dropdown with its total, the duplicate title/tagline are absent, and Search, Export and Project actions remain available. The project page is left open. Auto Capture remains paused; no capture content, organization, clipboard, or capture preference was changed for verification.

Visual evidence is from native synthetic render fixtures; live verification used accessibility. The installer changes the app bundle, not the archive. No remote push, downloadable release, or App Store/TestFlight submission was performed.
