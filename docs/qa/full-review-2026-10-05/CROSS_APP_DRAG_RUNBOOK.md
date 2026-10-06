# Isolated cross-application drag check

This is a source audit and staged runbook. No fixture was built, signed, launched or exercised by this audit. Wait for the coordinator's final native GUI suites to finish. Use fictional data only. Do not reuse an already-running receiver, the installed DaBin archive, unrelated documents, a public upload page, or the ordinary clipboard.

## Existing fixture boundaries

| Fixture | Safe data/service behavior | Coverage and limitations |
|---|---|---|
| `native/Tests/NativeContentDragTests.swift --manual` | Creates a new `DaBinNativeDragManual-UUID` temporary directory and a fictional text file. The manual branch constructs no archive, preferences object, AppState, coordinator, preview service, AutoCapture, reminders or notification service. It never executes the automated branch's general-pasteboard revision read. No network API is invoked. | Uses the production `nativeContentDrag` gesture and real AppKit dragging sessions. Payloads are simple `NSString`/`NSURL` writers, so it does **not** prove the archive-backed `ExplorerTransfer` snapshot/export path. Its built-in NSTextView is a same-process receiver. Manual mode activates immediately at launch and removes its temporary source file on quit; finish destination-byte verification while it stays alive. |
| `native/Tests/NativeDropQAMain.swift` | Creates `DaBinDropQA-UUID/IsolatedArchive`, fictional text and a fictional file. Uses only `CaptureStore`, `InputService` and `RobotView`. `onPaste` is not connected; accepted drag pasteboards are passed explicitly. No preference store, preview service, coordinator, AutoCapture, notification service or network task is started. | Exercises the production incoming robot/drop importer, including physical Finder or local-browser input when deliberately supplied. It does not exercise outgoing archive transfer. It activates immediately at launch and writes its summary next to its bundle. The original build script compiles all direct-channel production files and replaces a fixed `/private/tmp/DaBin Drop QA.app`; avoid that script during this frozen run. A separately compiled fixture against the verified current module would need its own fresh app stage; do not execute the old app. |

No forbidden service is constructed on these paths; this is a source-level boundary, not an OS-enforced network/privacy sandbox. A linked test module contains other production types without starting them. AppKit may use preferences belonging to a fresh fixture bundle ID; the fixture does not read or write DaBin's production preferences. The two older review harnesses under `docs/review-2026-09-30/harness` use dated fixed roots and are not substitutes for a fresh UUID fixture.

## Stage the outgoing manual fixture after final GUI QA

The QA-only [stager](stage_manual_drag.py) derives one exact cache path from the supplied passing full QA report. It verifies all current report inputs, the coordinator's production fingerprint, module cache inputs/output hashes, fixture source and executable hashes, and unchanged source/cache after preparation. It does not scan caches or compile. Prefer the final Store report when available; the result still uses an ad-hoc signed, unsandboxed test app.

This remains the default `--scope full-pass`. An explicitly authorized [manual-fixture-only scope](MANUAL_DRAG_SCOPE_PROPOSAL.md) can instead accept current requested functional PASSes alongside a retained performance-budget failure. It keeps `overallQAStatus: failed` and `releaseAcceptance: false`; it does not certify full application QA. Every supplied receipt must match current inputs, and unresolved functional failures are rejected. The implementation has passed 13 offline synthetic receipt checks; no real fixture has been prepared by those checks.

```sh
cd '/Users/roeylibfeld/Documents/KARI Creatives/DaBin'
export PYTHONDONTWRITEBYTECODE=1
python3 -B docs/qa/full-review-2026-10-05/stage_manual_drag.py \
  --report "$DABIN_FINAL_FULL_QA_REPORT" \
  --expected-source-fingerprint d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa

# Only after native GUI QA finishes; stages and ad-hoc signs copies, never opens:
python3 -B docs/qa/full-review-2026-10-05/stage_manual_drag.py \
  --report "$DABIN_FINAL_FULL_QA_REPORT" \
  --expected-source-fingerprint d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa \
  --prepare
```

It returns a fresh `/private/tmp/DaBin-CrossApp-0.4.41-.../DaBin Fictional Drag QA.app`, UUID bundle identifier, staged executable/library hashes, `staging-receipt.json`, an empty Finder destination, and a local browser receiver. The stager has no launch option. It does not delete or replace existing apps, processes, receipts or destinations. Until an explicit later open, there is no new application process and foreground ownership is untouched.

When the coordinator is ready to begin CUA interaction, open **that exact returned app**. Its plist sets `DABIN_NATIVE_DRAG_MANUAL=1`; the explicit CLI also supplies the argument so there is no ambiguity:

```sh
/usr/bin/open -n "$DABIN_FRESH_DRAG_APP" --args --manual
```

Do not invoke this command during another GUI suite. Confirm the window title is “DaBin Native Drag QA — fictional samples” and the source controls include text/link/file/mixed choices. If it closes or runs automated assertions instead, stop and retain the logs rather than interpreting that as a manual pass. Keep the unique app path and bundle identifier in evidence and quit only this fixture when done.

## Representative destination checks

1. **TextEdit:** create a new untitled document through CUA. Drag “Fictional DaBin note” from the fixture into the document. Verify exactly those 20 ASCII characters, with no extra newline or replacement text, and that the fixture's preview count stays zero. Use only this newly created document; close without saving when finished. This source contains no non-ASCII Unicode: Unicode/combining-mark/emoji/RTL fidelity remains **UNTESTED**. Typing a new string into the same-process receiver and dragging its text selection would exercise NSTextView, not this production source, and cannot close that gap.
2. **Browser:** try the returned `local-drag-receiver.html` as a local file in a fresh tab. If file URLs are unsupported, use the fixed-route loopback fallback below. The supplied page blocks network resources, connections and forms through CSP; it has no fetch, upload, clipboard, persistence or navigation code. Every document drop cancels default browser navigation. Drop each fictional note/link/file/mixed payload onto its labelled region. Inspect the raw `text`, `uri`, `types`, `files`, `noteExact` and `fixtureBytesExact`, and preserve the displayed result/screenshot. For the link, the sole nonempty, noncomment URI-list entry must equal `https://example.invalid/fixture`; if the browser exposes it only as `text/plain`, record that actual representation and compare it exactly. This is a region drop; the page has no URL input, so browser input-field acceptance remains **UNTESTED**. Never drag the URL onto the browser address bar or an upload service.
3. **Finder:** open only the returned empty `Finder received fictional files` directory. Drag `Fixture.txt` into it. Verify exactly one new file, its exact bytes (`Fictional DaBin attachment for native drag QA.\n`) and unchanged source content. The production source declares external copy only. A Finder copy is meaningful evidence only if the destination file actually appears and verifies; a cursor/session start alone is not a pass.

The HTML fixture reads only an explicitly dropped file of at most 1 MiB into that tab. It reports exact expected text-file bytes rather than performing uploads. It has no disk write or app-monitoring service. It is an actual browser destination, not a live upload backend or native sandbox-grant test.

The current manual mixed source passes three separate pasteboard writers to AppKit: the note, URL and file. `DataTransfer.types.length` counts exposed formats, **not native drag items**. Browser engines and native destinations may accept only some representations or coalesce textual items. Record each destination's received contents and exact supported subset. Only count all-three acceptance when the note and URL are independently preserved and exactly one correct file is received. A Finder result containing only `Fixture.txt` establishes a supported file copy, not delivery of all three items. A same-process receipt or the source's “Drag ended” status alone establishes no cross-app result.

## Optional fixed-route loopback browser fallback

The QA-only [server helper](serve_local_drag_receiver.py) is prepared; only Python syntax and argument help have been checked. It has **not** been started, its HTTP/CSP behavior has **not** been exercised, and no browser tab was opened. Wait until the coordinator releases the stage after full GUI QA and supplemental stress.

```sh
cd '/Users/roeylibfeld/Documents/KARI Creatives/DaBin'
# Later, in a retained, owned terminal session; no automatic browser/app launch:
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  docs/qa/full-review-2026-10-05/serve_local_drag_receiver.py --serve --duration 900
```

The helper binds only `127.0.0.1` with an OS-selected port. It copies only the fictional receiver HTML into a new `/private/tmp/DaBin-Drag-Receiver-.../` directory and serves in-memory bytes on the single random `/<token>/receiver.html` path shown in its receipt. The workspace, source fixture files and temporary directory contents are never exposed through arbitrary paths or a directory listing. Do not replace it with `python -m http.server` rooted in the workspace. Requests with other paths, Host values or foreign Origins are denied; methods that might carry uploads are rejected without reading their bodies. The page's CSP denies outgoing connections, subresources and forms; the response also denies framing. No request data is retained beyond allowed/denied request counts.

Preserve the printed URL and owned PID, then explicitly open that exact URL in a fresh browser tab through CUA. Confirm the title and “No drop received” state before the first real drag. A browser page load proves receiver availability only. Retain its receipt, destination results and screenshots separately from the source fixture receipt. The helper stops after 900 seconds by default (maximum 1,800), or on SIGINT/SIGTERM sent to its exact owned process. It leaves its small staging directory and stop receipt for review. No unrelated server or process should be reused or stopped.

## Evidence and remaining scope

Record source candidate/fingerprint, distribution module hash, staged binary hash, exact fixture process identity, destination app/version, result per attempted payload, before/after fixture preview count and destination byte evidence. Use a fresh receipt for this run, not older receiver logs. The earlier October 3 attempt reported CUA source-window events while global pointer location did not move; cross-application completion was unverified. If the current controller cannot complete a physical drop, retain that limitation without converting it into a pass or changing system input permissions.

These checks can reduce the cross-app gesture/representation gap for the observed apps. They do not certify archive-backed outgoing snapshot lifetime, all file types, original-byte delivery after source deletion, App Sandbox transfer grants, a real browser upload service, Developer/Store signing, installed-app behavior, or the hardware/OS matrix. Registered outgoing snapshot/batch/process tests remain separate evidence. A stronger archive-backed interactive source would need a QA-only fixture using a UUID `CaptureStore` and `ExplorerTransfer.pasteboardWriters(..., stagingRoot: ownedUUIDDirectory)`; it must not be improvised by seeding the installed archive.
