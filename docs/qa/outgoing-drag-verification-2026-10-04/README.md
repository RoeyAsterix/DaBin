# Outgoing drag verification — DaBin 0.4.30 (85), 4 October 2026

**Implementation fixes are installed and 13 focused native suites pass (1,753 checks). Physical drops into external apps and browsers remain unverified.** Do not treat a successful native payload test as proof that every receiving application accepts a completed drop.

## Gaps found and fixed

- Static comment captions in Daily/Inbox, Week and grouped cards now drag their complete exact comment text, preserving whitespace and Unicode despite visible truncation.
- Recognized-text captions transfer the saved capture/original rather than the short displayed excerpt.
- Detail display titles, Inspector titles and the static TASK/COMPLETED label in task details now transfer the full saved capture. Non-task Detail and Inspector titles now act as whole-capture drag surfaces rather than allowing substring selection; selectable original body/source/OCR text and editable fields keep native text behavior.
- Expanded batch and hourly headers now transfer every capture in order, matching collapsed collection summaries. Copy, collapse, completion, project and editor controls remain separate.

Existing text, URL, saved-file and original encoded image representations, mixed selections, copy-only external operations, source preservation and independent general clipboard behavior remain intact. [Surface coverage](surface-coverage.json).

## Automated verification

All **13 focused suites / 1,753 checks** pass with stable run inputs, and their production source hashes match the final signed build receipt. [Summary](verification-summary.json).

The new **135-check CaptionDragTests** mounts production views, resolves the actual drag closures and checks native hit regions at rendered captions. It tests exact long Unicode comments, live comment updates, whole capture/collection writers and ordering, independent controls/editors, unchanged records/originals and unchanged general clipboard. [Caption run](caption-regressions/report.json).

The new **40-check ExternalTransferProcessTests** launches a separate consumer process to read six interleaved production payloads from a unique private native pasteboard: Unicode/multiline text, PNG, URL, binary file, JPEG and task. The consumer materializes both promised image encodings, compares complete bytes and SHA-256 hashes, and verifies native file-reader order. Both processes preserve the source records, files and general clipboard. **This proves cross-process data availability; it does not exercise a physical drag, sandboxed destination grants or browser acceptance.** [External-process run](external-process-regressions/report.json).

Other passing suites: ExplorerTransfer (99), CaptureAction (31), CaptureClipboard (29), ProjectWorkspaceView (209), ProjectWorkspaceCard (263), DetailPreviewInteraction (110), CollectionCardPresentation (350), ExplorerCaptureCardPresentation (267), NativeContentDrag (38), SearchInput (65), and AutoRecordIndicator (117). [Candidate run](candidate-first-run/report.json).

The first CaptionDrag fixture incorrectly marked indexed text ready with extractor version 0; normal metadata validation correctly rejected it before view testing. The fixture now sets the current extractor version. Production validation was unchanged, and the corrected suite passes. The failed first attempt and [correction receipt](caption-fixture-correction.json) are retained.

## Physical drop status

The fresh separate-app attempt used the exact installed native drag bridge with fictional local text/link/file samples. The automated file gesture began a source drag without opening a preview. The logged global mouse remained stationary, and the receiving app recorded no drag-enter or completed-drop callback. The source session ended during cancellation. This reproduces the desktop-controller limitation in the earlier outgoing-drag report, rather than establishing success or a source-confirmed external-drop defect. [Attempt evidence](external-attempt/verification.json), [source trace](external-attempt/source-events-2.jsonl), [receiver trace](external-attempt/receiver-events-final.jsonl).

Two fictional native test windows remain open for the requested physical check: drag **Drag file: Fixture.txt** from **DaBin Native Drag Source Verification** into the outlined target in **DaBin External Drop Receiver Verification**. A real successful drop creates a receipt containing matching source/copy hashes and retained-original status under the receiver output directory recorded in the attempt evidence. No successful receipt or user confirmation was received during this verification.

A [local-only browser target](fixtures/browser-drop.html) is prepared for a separate browser check. It shows DataTransfer types, complete text/URL and file hashes, plus an ordinary text field with no custom drop handler. It uploads nothing and blocks network connections. It has not been used to claim a browser pass. Finder, sandboxed recipients, particular third-party apps, and a browser matrix remain outside the verified coverage. Receiving targets must support the supplied content type.

## Build, installation and scope

**0.4.30 (85) is installed at `/Users/roeylibfeld/Applications/DaBin.app`.** Both installed executable hashes and the source fingerprint match the signed [build receipt](build-receipt.json), with strict signature validation and a recoverable previous-app backup recorded in [installed verification](installed-verification.json). The app reopened successfully; Auto Capture remains paused, all 60 saved items remain, the existing quick-capture draft is preserved, and Search is empty/focused after Command-K.

The reproducible frozen source is `/private/tmp/dabin-drag-verification-20261004/native`, based on the previously installed 0.4.29 candidate. It adds six scoped production-source changes and two registered tests. Ongoing shared tutorial edits remain preserved and excluded; [comparison manifest](frozen-candidate.json) and `retained-tested-sources/` record the tested scope. Generated Xcode files, [source packaging](source-packaging.txt), [metadata](metadata-check.json), warnings-as-errors Release compilation and diff checks pass.

This is local ARM64 QA on the recorded macOS/SDK versions, not minimum-OS certification or a public/App Store release. No personal capture was transferred into another app, no user capture setting was changed, and no data was uploaded.
