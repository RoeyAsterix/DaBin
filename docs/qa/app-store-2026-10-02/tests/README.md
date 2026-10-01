# Local App Store preparation tests

## Final frozen native Release run

**73 of 73 registered suites pass, with 87,546 reported checks, zero failures and no input changes during execution.** These counts include per-pixel corner/rim and robot choreography assertions, not that many independent user workflows. The updated privacy suite passes 37 checks; packaging-facing update configuration passes 27. Robot closing passes 400 observed native/encoded-video checks, and window chrome passes 50,904 geometry/coverage checks.

- [Final source-bound full-run receipt](full-release-final/report.json)
- QA source fingerprint: `9039172fca3d6b400c7ed1ec3ecd1551210d7eca23cd69a524c1efb00893e3fe`
- Receipt SHA-256: `7a4521e405437c7d3ce93715d85f5246f06e315addf28b0cd82fb90b00787bfa`
- Run: `2026-10-01T22:58:33.980836Z` to `2026-10-01T23:06:05.963263Z`, approximately 7 minutes 32 seconds, including a fresh optimized 106-source test-core compile.
- ARM64, macOS 26.6.2, Swift 6.4, macOS SDK 27.0; deployment target macOS 14.

The exact full-suite command below was repeated after privacy, source Info configuration marker and packaging patches froze. After completion, every listed input still matched its receipt. In particular, final `Resources/Info.plist`, `Resources/PrivacyInfo.xcprivacy`, `Resources/PrivacyPolicy.md`, `Sources/DaBin/PrivacyInformation.swift` and `Tests/PrivacyInformationTests.swift` hashes are bound in the receipt. This final run, rather than the older baseline, is the current functional regression evidence.

The scope and distribution/runtime limitations explained below apply equally to this final run. Neither passing functional tests nor a locally built archive implies Apple approval.

After the archive-only preflight correction, [focused UpdateConfiguration passed 27 checks](post-packaging-update-configuration/report.json). Every final full-suite source/resource/test input still matches its receipt. This focused run is supplementary packaging-text coverage, not another full run or 27 new independent checks to add to the full-suite total.

## Full native Release baseline

**73 of 73 registered suites pass, with 87,536 reported checks and no input changes during execution.** Counts include extensive per-pixel corner/rim and robot choreography assertions; they are not 87,536 independent user scenarios.

- [Source-bound full-run receipt](full-release-baseline/report.json)
- QA source fingerprint: `74c489abe2155deea7edd42aea7a6b78d79d51a2acccdf046224c8913a8829c3`
- Receipt SHA-256: `d2dd437689f945fc096ad4dc4fc401bef85a311fa9db1bb116d051b1aef75c89`
- Run: `2026-10-01T22:45:55.292653Z` to `2026-10-01T22:51:00.696645Z`, approximately 5 minutes 5 seconds.
- Environment: ARM64, macOS 26.6.2 (25G83), Swift 6.4, macOS SDK 27.0, target `arm64-apple-macosx14.0`.

Exact command from the DaBin project directory:

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 native/scripts/run_qa.py --configuration Release --timeout 180
```

The command was run with scoped native test execution after a preliminary tool-sandbox run could not reliably create/read the generated archive documents or complete AppKit lifecycle checks. [Preliminary failure and interruption details](PRELIMINARY-SANDBOX-RUN.md) remain separate and are not included in this passing receipt. No test assertions or production sources were changed to obtain the pass.

Coverage includes project archive ownership and original-byte preservation, safe backup/restore, recoverable deletion, search/OCR, draft and task lifecycle, timer acknowledgment, clipboard retention, Auto Capture opt-in and fake/private-input routing, native navigation, preview-open actions, two-second in-app feedback, tooltips, responsive layout, all eight resize grips, continuous corner coverage, canonical robot appearance, and real offscreen close recordings. Window/resize checks observed two attached screens. Reminder tests use fake clients rather than scheduling system notifications.

The test module is optimized with warnings as errors and **`DABIN_DIRECT_UPDATES`**. This is functional regression evidence, not a claim of a distribution-signed Mac App Store runtime pass. Store-only compilation, archive packaging, effective sandbox entitlements, provisioning, Organizer validation, real permissions, VoiceOver usability and Apple review remain separate release gates. Targeting macOS 14 does not establish testing on a macOS 14 machine.

All captures, input events and stores are fictional and isolated. Some authorized own-process QA windows temporarily activate their test executable to validate native keyboard focus. Tests never send global synthesized input, operate the installed DaBin app, touch its personal archive/preferences, read/write the general clipboard, open an external app, request notification permission, deliver system notifications, contact external services, install, sign, upload or submit.

## Offline distribution tooling

[Thirty Python tests pass](notarized-distribution-tests.log) for the direct-distribution tool's refusal and command-construction rules. These use temporary fixtures and mocked signing/notary/policy commands, not real Apple services.

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest discover -s native/Tests -p 'test_notarized_distribution.py' -v
```

After the frozen preparation patches, [all 45 offline Python tests pass](offline-python-final.log): the 30 distribution tests plus 15 App Store metadata validator tests. Metadata limits include plain text, version/Bundle ID binding, Unicode byte budgets and failure-closed submission completeness. Passing the validator deliberately never implies Apple approval.

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest discover -s native/Tests -p 'test_*.py' -v
```

After the final packaging correction, [these 45 tests pass again](offline-python-post-packaging.log), and [all 32 Store preflight/builder regressions pass independently](store-preflight-regressions.log): **77 offline Python tests total**. The latter cover minimal sandbox capabilities, missing/incorrect final signed identifiers, privacy declarations, Store profile consistency/expiry, direct-payload rejection, Store-only binary markers, safe output paths and the distinction between a development archive and final distribution.

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 native/scripts/test_app_store_preflight.py
```

The independently reviewed archive-only relaxation does not weaken final `--app` gates. Final distribution still requires the configured team, Store authority, strict signature, reviewed entitlements, matching signed app/team IDs, an unexpired macOS Store profile with certificate membership, exact current resources/fingerprint and no direct-update helper/downloader. A development archive may omit app-ID claims while retaining its separate team, strict-signature and sandbox checks. This is local structural verification, not a substitute for Apple's trust or Organizer validation.

## Synthetic media integration

**39 of 39 checks pass again on final frozen sources** in the separate `native/scripts/test_media_integration.sh` command, with external website smoke testing disabled. Its exact source inputs were unchanged during compilation and execution. [Final source-bound media receipt](media-integration-final-report.json) and [final full log](media-integration-final.log) are retained alongside this document. The [earlier baseline media receipt](media-integration-report.json) remains separately preserved and is not substituted for the final run.

PDFKit, QuickLook and AVFoundation render nonempty bounded thumbnails from synthetic PDF, RTF and moving video fixtures. Original and managed bytes remain unchanged. Hidden, non-key production PDF views fit both portrait and landscape pages at wide and narrow sizes. Decoded early/later video frames genuinely differ; no model-generated footage is claimed.

- The final media source fingerprint and executable SHA-256 are in its receipt.
- This receipt excludes resources that media tests do not read and does not cover external website previews. After it finished, all final full-suite inputs still matched their own receipt.

## Input changes after the baseline

The baseline receipt binds its exact listed inputs. Subsequent source, resource, privacy or test changes require appropriately scoped reruns, and significant behavioral changes require another full run. Packaging scripts outside the runner's snapshot are audited separately; rerun `UpdateConfigurationTests` after packaging edits freeze because it reads those scripts.
