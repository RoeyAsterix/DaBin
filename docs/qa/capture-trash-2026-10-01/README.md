# Visible caption trash — 0.4.5 (58)

## Change

Capture and task cards now expose a small trash icon beside Copy. It remains available on minimized cards and in Daily, Inbox, Search, weekly cards, the workspace, Explorer, capture details and task attachments. Grouped cards retain their existing batch confirmation and now expose its trash action directly. The hourly minus remains a collapse control.

The shared `CaptureTrashButton` uses the existing icon style, tooltip preferences, keyboard behavior and an item-specific accessibility label. It requests confirmation before moving the selected capture to Recently Deleted. Existing Undo and restore behavior remains available; original files at their source locations are kept. Removal controls are disabled during archive operations or an in-progress removal.

Production changes: `CaptureCards.swift`, `WorkspaceItemCard.swift`, `ExplorerItems.swift`, `WeeklyScreen.swift`, `DetailScreen.swift`, `TaskAttachmentsView.swift`, and `GroupedCaptureCard.swift`. Version metadata and release documentation identify build 58. Regression coverage is in `RedesignInteractionTests.swift` and the version expectation in `UpdateConfigurationTests.swift`.

## Verification

- ARM64 Release build succeeded; installed executable, build inputs and QA inputs match.
- All six requested suites passed: CaptureRemoval (76 checks), CaptureAction (31), RedesignInteraction (62), UpdateConfiguration (27), WorkspaceWindow (209), and WeeklyWindow.
- Native accessibility tests press the visible trash button on regular and minimized cards, including cards without Copy. They check confirmation, cancellation, selected-record removal, preserved neighboring records and Undo with original text, task status and provenance.
- The 380-point production card render was visually inspected: trash is visible, aligned beside Copy and does not clip the title.
- Deterministic project validation, whitespace validation and strict app signature verification pass.
- The installed app was relaunched from `~/Applications/DaBin.app`; the Daily window and three visible trash controls were verified through scoped accessibility inspection.
- Private archive and preferences backup completed before installation: 228 files verified. All 40 original records retain their data, except one normal expired focus timer; all 16 managed attachment originals remain byte-identical. No personal capture content is included in this report.

This was focused regression QA, not a new full-suite run. Destructive interaction tests used an isolated fictional archive; personal captures were not deleted for testing. GitHub and TestFlight publication were not performed.

## Evidence

- [QA report](qa-report.json)
- [Release build receipt](build-receipt.json)
- [Installation and data verification](installation.json)
- [Compact capture card](capture-trash-380.png)

![Trash beside Copy on a fictional capture card](capture-trash-380.png)
