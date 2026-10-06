# DaBin testing and App Store review preparation

**0.4.41 (96) — DRAFT; submissionReady=false. No Apple upload, submission, account change, or public publication performed.**

The final Store Release campaign tested all 126 registered suites: **125 passed and one failed**. The sole failed suite is zoom responsiveness under the 5,000-item workload. The subsequent unsampled 10-minute workload completed without a recorded crash or timeout but failed the same unchanged timing limits. Local preparation is recorded below; these results do not certify Apple approval.

## Verified results

| Check | Result and scope | Evidence |
|---|---|---|
| Full Store Release |125/126; unchanged source/test inputs; overall FAILED only performance |[Exact report](final-store/full-qa-report.json) |
| Direct focused regressions |3/3; live project/card edits and native drag; 918/782/38 checks |[Report](final-candidate/focused-functional-report.json), [four-image review](final-candidate/visual-review.json) |
| Durability |8,586 checks; 1,000 seeded captures, 320 operations, 25 reopen comparisons, four owned-process kill boundaries |Full Store report |
| Flow/action, graphics, video |11,674 semantic flow checks; 109,041 graphics/lifecycle checks; 113 video checks |Full Store report and [graphics receipt](final-store/graphics/visual-animation-stress-report.json) |
| Search typing/paste |65 native search-input checks, including keyboard paste |Full Store report |
| Unsigned Store packaging |Compile and unsigned packaging preflight passed; exact frozen source/version |[Supplement report](final-supplement/report.json) |
| Xcode smoke |2/2 passed, zero failures; retained xcresult independently read back |[Readback](final-supplement/xctest-readback-receipt.json) |
| Enforced App Sandbox |Save 12 checks, reopen/export 19; ungranted read/write denied in both; fictional originals persisted |[Fresh-temp rerun](final-supplement/sandbox-temporary-rerun-readback.json) |
| Privacy |39 registered checks; separate production-view render and all four light/dark top/bottom images inspected |[Visual receipt](final-supplement/privacy-visual-review.json) |
| Offline tooling |90 Python tests passed earlier; unchanged 75 carried forward, affected 15 metadata cases rerun PASS; current project/static/draft PASS, strict correctly incomplete |[Final receipt](final-offline/verification.json), [original 90](candidate1-python/verification.json) |
| Direct-channel updater |2/2 suites;48 software update+41 channel checks PASS |[Final direct receipt](final-offline/direct-updater-report.json) |
| Local install |0.4.41 (96), exact frozen source/executable,strict signature,previous app backup; both archive roots byte/structure hashes unchanged |[Installation receipt](local-install/verification.json) |

## Performance remains failed

| Run | Input-to-layout p95 | Steady-timer p95 | Existing limits |
|---|---:|---:|---|
| Final Store, 30 seconds |51.3154 ms |61.2394 ms |50 ms /33 ms |
| Sustained, 600.019883 seconds |53.6320 ms |63.0316 ms |50 ms /33 ms |

The sustained fixture retained 5,399 captures, 2,000 managed originals and 1,000 thumbnails. It performed five zoom/navigation cycles spread over ten minutes, a 100-record burst and two-second arrivals with idle intervals; this was not continuous ten-minute zoom. It preserved recorded anchors/selection and completed its owned process normally with exit 1 at the timing assertion. RSS was 232,751,104 bytes initially, 250,068,992 at the last cycle and 247,742,464 at the measured end; maxRSS 251,412,480. These are bounded observations, not proof of no leaks or an energy benchmark. [Raw measurements and readback](final-supplement/sustained-readback.json).

Layout and callback changes reduced the 30-second input p95 from the baseline 73.27 ms to 51.32 ms. The 50/33 ms gates remain unchanged and unmet. An AppKit reentrant NSTableView warning remains in the logs. [Candidate comparison](layout-comparison.json), [profile analysis](layout-candidate-4/profile/analysis.md).

## Evidence integrity and corrected fixture failures

Production source fingerprint is `d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa`; [source freeze](final-candidate/source-freeze.json). It differs deliberately from the QA inventory fingerprint, which also includes selected tests/resources. The final Store module SHA-256 is `9664ad04df275e317cb5911809b9f9b5f907e5c3033ed14a05723c29d1a941d9`.

The original [supplement coordinator report](final-supplement/report.json) remains failed and unchanged. Its XCTest command actually succeeded; the evidence collector assumed a standalone test bundle rather than the embedded PlugIns location. The separate readback confirms both cases and unchanged unsigned executable. xcresulttool added one database index to the copied result bundle; all 31 original manifest files remain byte-identical. The collector was corrected only for future QA runs.

The first sandbox attempt failed before launch because FileProvider FinderInfo metadata prevented signing. The unchanged fixture was rebuilt in a fresh `/private/tmp` directory and passed under its own App Sandbox. Its unique container and denial checks are fixture evidence, not distribution signing, real picker/bookmark grants, or the installed product's sandbox transfer acceptance. Copied evidence hashes and both attempts are retained.

## Manual and distribution limits

The isolated native drag delivered the exact fictional ASCII note to its own receiver with zero preview clicks. A fresh local browser receiver loaded; it still displayed No drop received. An owned blank TextEdit document was created and closed without editing/saving. Physical TextEdit/browser/Finder delivery remains UNTESTED: the UI bindings did not provide documented cross-window coordinate mapping, and app launch control stalled. The fixture quit was verified, the test tab closed and the loopback servers expired. [Manual receipt](manual-drag/receipt.json), [remaining runbook](CROSS_APP_DRAG_RUNBOOK.md). Registered cross-process Unicode/file-byte tests are separate evidence and do not establish a physical gesture.

No signed Store archive or installer package was created in this campaign. The local signing audit found matching Apple Development/Distribution certificates and an unexpired Store profile, but no Mac Installer Distribution identity. Protected private-key use and final distribution packaging/validation remain open. [Signing audit](local-signing-assets-candidate2/README.md). Archive work is held while release acceptance fails; no provisioning assets were downloaded or created.

Host is ARM64 macOS 26.6.2, Xcode 27.0/SDK 27.0. Minimum macOS 14, the current shipping macOS 27.0.1, another physical Mac, full VoiceOver, real permission/bookmark/notification flows, realistic capture energy and IPv6-only preview networking still need acceptance. Two attached screens were covered by registered window tests; physical monitor movement remains separate.

## Review materials and owner gates

Current screenshots, guide, content document and draft ZIP are complete from the same frozen Store module: three opaque RGB 1440×900 screenshots, a 15-page DOCX and a 2-page guide. [All-page/artifact verification](review-pack-final-verification.json), [visual inspection](review-pack-final-visual.json), [coordinator completion](completion.json). The local app is installed but was left closed; installed-product launch/manual acceptance is pending. Previous packs and failed/intermediate evidence are preserved. [Earlier detailed campaign draft](README-draft-through-20261005T221043Z.md), [retention index](retained-evidence-index.json), [review requirements](../../app-store/APPLE_REQUIREMENTS_2026-10-05.md).

The configured public privacy URL returned older 4 October text at the recorded check; bundled policy is 5 October. [Preserved mismatch](policy-parity-after-correction/verification.json). Public parity requires later authorized publication and verification. Legal copyright/rights, maintained support contact, private review contact, price/territories/release method and trader status remain unanswered owner inputs. Apple account/build availability, agreements and compliance declarations were not verified or changed. Strict metadata correctly remains incomplete.

Completed local preparation at 2026-10-06T03:36:21.389636+00:00. Overall QA/performance remain FAILED and submissionReady=false. No upload/submission/publication was performed. [Final frozen metadata checks](final-metadata/verification.json).
