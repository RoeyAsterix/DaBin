# Outgoing drag reliability — 2026-10-05

DaBin outgoing drags previously retained a mutable managed archive URL. The baseline fixture moved captures into another project before receiving applications requested their representations, and eight delayed transfer lanes failed. The current implementation publishes isolated regular-file snapshots and keeps original file/image bytes available after filing, source deletion and publication release.

Ordinary original filenames remain exact. Oversized names retain whole characters and a recognizable extension; duplicate and case-equivalent names in a selection receive bounded suffixes. Snapshot creation uses a validated file descriptor and a copy-on-write clone when available, with bounded streaming fallback. It never substitutes a symlink, historical source path or decoded/re-encoded image. Active snapshots survive cleanup; complete inactive owned snapshots become eligible after 24 hours. The `/var` and `/private/var` identity mismatch found during testing is corrected.

The existing native NSURL and lazy encoded-image drag formats, text/link representations and internal capture IDs are preserved. Dragging does not change source metadata or the general clipboard. Foundation item-provider file representations and generated daily Markdown also use stable snapshots.

## Verified results

The final production fingerprint is `24e49b499b3e8977e2e562c72e1c52a4fe8fd93f2d9f3d4eda650170b2610398`, with 169 canonical inputs. Both final native runs and the unsigned Store candidate record unchanged inputs.

- 13 affected Release/App Store suites passed, totaling 3,334 native checks. This is a selected campaign out of 126 registered suites.
- The nine-file native NSURL batch verifies exact bytes, names/order/IDs, real filing/trash/permanent removal before delayed reads, occupied-target preservation, immutable original metadata and reads after publisher release.
- A separate consumer process verifies six mixed production items, Unicode text/URLs, PNG/JPEG data and saved-file hashes.
- Projects, Captions, internal native dragging, previews, compact cards/collections and project ZIP exports passed. The project workspace fixture contains 1,000 captures.
- 32 packaging unit tests and deterministic project generation passed. The actual unsigned arm64 Release binary and Info.plist were checked for 0.4.33 (88), bundle ID, source fingerprint and executable hash; packaging preflight passed.

See [verification.json](verification.json), [campaign.json](campaign.json), and the raw [runs](runs/) and build logs. Initial failures are preserved: baseline stale URLs; an experimental file-promise initializer/image/metadata approach; active-directory key mismatch; and the batch fixture's retired trash-record lookup. The lookup was corrected to use canonical live/trashed records without weakening byte/lifetime gates.

The experimental NSFilePromiseProvider path was removed from the final implementation. Private-board callbacks do not prove a completed accepted drag; ten controls, including original providers, produced zero fulfillment callbacks. Probe source, raw results and the original experimental test are retained in [experimental-promise-probe](experimental-promise-probe/). The final native URL protocol is verified independently. [Apple lifecycle evidence](apple-drag-test-boundary.md) records the transport boundary.

## Limits and testing notes

The actual receiving app and its installed version remain unknown. The reported `OD_PROTOCOL_PROXY_FAILED` occurrence was not reproduced. Public receiver research distinguishes that token from DaBin's independently demonstrated lifetime defect; see [receiver research](receiver-research.md). A physical drop into that app, its live upload service, sandbox grants and signed installation still need verification. Large cross-volume drag-start responsiveness and a hardware/OS matrix were not established.

Historical strict zoom performance and framework-native table warnings remain open; this change does not claim all previous QA findings fixed.

For internal testing, try documents and images from Projects and Captions, multiple files with the same name, and a delayed upload followed by filing or deletion in DaBin. Check full original bytes and names, ordinary text/link drags, internal move/Undo and source preservation. Distribution signing/upload/processing and the current-build tester email are separate pending milestones; this unsigned compile is not a TestFlight upload.
