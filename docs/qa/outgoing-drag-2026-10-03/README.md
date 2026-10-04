# Native outgoing drag — DaBin 0.4.27 (82)

Cards now publish their saved content through native multi-item AppKit dragging. Files retain native file URLs, images also promise their exact encoded original, links carry URL and text representations, and text/tasks/project notes carry readable original text. Project selections and collapsed collections publish each item separately. The drag pasteboard is independent of the general clipboard. External operations are copy-only and do not remove the saved source.

Content previews and titles support dragging in project grids, daily/weekly cards, grouped/hourly collections, Clipboard/Shelf cards, search, Explorer, task attachments and saved-file detail previews. The Scratchpad heading drags its full current text. Selection/completion/menu/editor controls retain their own interaction areas. Internal project reordering keeps its explicit marker alongside public content and clears its transient state on completion, cancellation or materialization failure. Filtered views can still drag outward.

The earlier export simplification is retained: one contextual Export project / Export selected (N) action opens a standard Save ZIP panel. Copy actions live in the existing Project actions menu. Shelf and Explorer export labels state their scope.

## Build scope

The isolated candidate is `/private/tmp/dabin-outgoing-drag-20261003/native`. It includes the already verified project Task/Note/Capture visual distinctions. Three unfinished robot source edits and three new AutoCaptureSign sources remain in the shared workspace; the candidate preserves the exact installed 0.4.26 robot implementations. `source-attestation.json` records every changed input and preserved difference. No concurrent edit was reverted.

## Validation

The first integrated run found a real cached-file-metadata issue in promised-image reads and an unsupported offscreen menu test. Transfer code now invalidates cached metadata and validates the current directory entry before a promise is materialized; the symlink-substitution failure test remains intact. The test no longer pretends an unmaterialized offscreen menu can be invoked. Newest-first uses the same non-reorder transfer path as the tested filtered view; direct Newest menu interaction is not claimed by this suite.

Native gesture coverage includes ordinary clicks, suppression of open-on-drag, neighboring controls, right/control clicks, hidden/removed sources, excluded checkbox regions in flipped/unflipped coordinates, empty/error payload cleanup, distinct mixed session items, original-byte preservation and unchanged general clipboard change count. Project tests resolve the actual rendered source closure and test selected image, text and live note payloads on a private pasteboard. All archives and test content are fictional and local.

All 12 focused Release suites pass, totaling 2,012 checks, with unchanged run inputs. Their 118 production-source hashes match the signed build receipt. The local installation is 0.4.27 (82); its executable SHA-256 and strict code signature match the tested build. The previous app is preserved in the backup path recorded by `installed-verification.json`. The three retained installed robot source files are preserved under `retained-installed-sources/` so the isolated build scope can be reproduced. See `final-qa/report.json`, `build-qa-link.json` and `installed-build-receipt.json`. This is focused local ARM64/macOS verification, not a full-suite, minimum-OS, browser-matrix or App Store distribution claim. A receiving application must support the dragged content type.

## Manual smoke check

The installed app reopened successfully, and its Project workspace shows the single Export project button and Project actions menu. Actual native text and URL drops into the same-process text receiver succeeded without opening the preview. The separate receiver recognized copy-only dragging in an earlier attempt, but cross-process drop completion could not be established through the desktop controller. A fixed source traced a completed native file session while the receiving app never got `performDragOperation`; the recorded global pointer remained unchanged during the injected gestures. This limitation is retained honestly in `manual-native-drag/verification.json`, not counted as a passed external-app test. No user capture was dragged or exported. The fixture windows were closed.
