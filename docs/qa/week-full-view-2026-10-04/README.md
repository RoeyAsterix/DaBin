# Week full-view QA — 4 October 2026

## Change

Selecting Week opens the existing expanded window on the current display, within its visible safe area. Every selected date stays visible, including empty dates; custom selections still support one to seven dates. Leaving Week restores the previous normal size and location. Native full-screen Spaces are not used.

Columns share the available width. Card previews, metadata and controls fit their columns instead of enforcing a zoom-scaled width. Imported batches and automatic-hour collections use the same compact cards when expanded. Each date scrolls vertically. A manually restored or narrowed window can scroll horizontally below the width required for seven usable columns; opening Week again restores full view.

## Verification scope

Native SwiftUI/AppKit fixtures use fictional local captures, isolated stores and fake notification clients. No personal capture content, clipboard reads or external requests are included in the QA artifacts.

The new layout suite renders the actual WeeklyScreen at 1024, 1280, 1440 and 1920 points, with 75%, 100% and 200% workspace zoom, in light and dark appearance, with collapsed and expanded collections. Additional fixtures exercise an empty week and a manually narrowed 420-point window. Window tests cover display-safe expansion, restoration, history, filters, custom selected dates and preserved zoom sizing on the available displays.

## Final automated results

All nine focused suites passed against unchanged inputs (native Release, direct distribution):

- WeeklyStateTests: 186 checks
- WindowTests: 260 checks across two connected displays
- WeeklyWindowTests: 101 checks
- HeaderInteractionTests: 290 checks
- CollectionCardPresentationTests: 350 checks
- CaptionDragTests: 147 checks, including native visible drag surfaces at 420 and 1024 points
- TimelineCalendarTests: 33 checks
- WeeklyLayoutTests: 3,168 checks, 50 native renders
- WorkspaceZoomTests: 94 checks

Total: 4,629 checks. Compilation uses the repository's warnings-as-errors settings. The project manifest check and `git diff --check` also passed. See `focused-qa-report.json` and `renders/weekly-layout-report.json` for exact scope.

Earlier failures exposed AX identifier propagation and assumptions in native fixtures about screen selection, navigation history and scroll visibility. They were corrected before the final passing run. No remaining failing checks are being excluded.

## Local installation and live check

Built Release for Apple Silicon, installed at `/Users/roeylibfeld/Applications/DaBin.app`, and launched through the existing Desktop `DaBin.app` link. The previous bundle was retained by the guarded installer. Two pre-existing production/development processes were quit normally before replacement; exactly one installed process was confirmed afterward.

Clicked the installed app's Weekly button. The window became `DaBin Week`, with all seven date-header accessibility controls and the seven-day footer present. The expanded window image measured 3024 × 1898 physical pixels. No live capture content or screenshots were saved to this report. Auto Capture remained paused.

Installed version: 0.4.31 (86), local Release build. This change does not publish a distribution release. Strict deep code-signature verification passed, and the installed executable hash matches the newly built bundle and receipt. See `local-build-receipt.json`.

Source fingerprint: `0faa48c95e1015998c437cdd047e63cd75c8aac0294d393d0373bcfc6de2ad8b`.
Executable SHA-256: `e0d4e955dea2bc337904d188802104c7f19d92a12dead5acc354f5bf3d442741`.


