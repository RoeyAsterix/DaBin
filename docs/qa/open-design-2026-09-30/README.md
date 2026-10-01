# Open Design implementation · DaBin 0.4.4 (56)

## Scope

Implemented the supplied `revisions_dabin-handoff-before-week-calendar.zip` in the existing native SwiftUI/AppKit application, including Explorer. Its SHA-256 matches the supplied checksum; archive integrity and safe extraction checks passed. The imported reference and provenance are retained under `design/imported-redesign-2026-09-30/`.

The redesign uses neutral light/dark surfaces, thin rounded cards, larger fitted previews, labeled primary navigation and a shared searchable project picker. Explorer keeps its real local folder model, transfers, daily documents and responsive inspector. The [80-feature map](FEATURE_PRESERVATION.csv) connects the reference inventory to current native code and regression suites.

New behavior includes in-place task conversion with guarded Undo, editable task titles, independent focus sessions, optional local planned time and explicit manual paste history. Timers, schedules, projects and paste history persist locally. Original capture identities and receipt dates remain authoritative.

## Issues found and corrected

- Compact project and Workspace headings were truncated; labels now remain readable at 380-point content width.
- Search field arrow keys did not navigate projects. Native field-editor command handling now supports Up, Down, Return and Escape; cancelling creation restores search focus.
- The paste-history plus initially opened the wrong popover mode. One presentation state now opens recording directly.
- Narrow nested weekly cards could overflow. Insets and compact timer controls were corrected; sparse weekly views use available width.
- A stale draft could overwrite a newly committed timer, schedule or Today order after restart. Recovery compares its committed baseline with current metadata, retains unrelated pending edits and respects newer durable changes.
- Recurring tasks lost source identity. They now retain source metadata while starting with fresh focus and paste history.
- Readable archive documents could label a copied link target as its source. They now distinguish a captured link from recorded origin metadata.
- Task detail actions occupied two rows unnecessarily. A compact action row gives that space to content.

## Verification

The final optimized ARM64 run passes **57/57 suites**, with no source changes during execution. This includes 79 timing/recovery checks, 66 provenance/export checks, 14 project-policy checks, 173 conversion checks and 47 native redesign interactions. All 108 shared QA/build inputs match; every current build input still matches the installed Release receipt.

| Verification | Result |
| --- | --- |
| `python3 scripts/run_qa.py --configuration Release` | 57/57 suites passed; complete registered suite |
| `python3 scripts/build_app.py --configuration Release` | ARM64 Release; warnings treated as errors; update helper included |
| `python3 scripts/generate_project.py --check` | Passed |
| `python3 scripts/app_store_preflight.py --static-only` | Source packaging checks passed; distribution approval is separate |
| `git diff --check` | Passed |
| Native rendering | 40 production-view renders reviewed across compact/expanded dimensions and both appearances |
| Installed application | 0.4.4 (56), exact Release executable; strict signature valid; running from the installed path |

Evidence: [full suite report](full-qa-report.json), [build receipt](build-receipt.json), [native interaction log](native-interactions.log), [render manifest](screenshots/open-design-renders.json), [local installation and preservation check](local-install-verification.json).

### Installed-app verification and data preservation

The guarded installer updated `/Users/roeylibfeld/Applications/DaBin.app` and retained the previous app bundle. A private pre-update archive/preferences backup verified 161 files. After launch, all **26 original capture identities and existing field values** were preserved (apart from schema metadata), and all **13 attachment originals were byte-identical**. The Desktop shortcut resolves to the updated installation.

Live native interaction confirmed Settings reports **DaBin 0.4.4 (56)**; existing capture, theme, retention and island preferences remain. Workspace opens the redesigned Explorer with Search, Paste, Files, Daily files, ZIP and Finder controls. The project picker opens with search focus and dismisses with Escape. Personal capture contents and backup payloads are excluded from this report.

### Main changed files

- Navigation and Explorer: `BoardView.swift`, `BuddyControls.swift`, `LibraryScreen.swift`, `ExplorerScreen.swift`, `ExplorerItems.swift`, and the shared `ProjectPickerView.swift`.
- Cards and detail: `CaptureCards.swift`, `GroupedCaptureCard.swift`, `HourlyCaptureCard.swift`, `WorkspaceItemCard.swift`, `DetailScreen.swift`, `InboxScreen.swift`, `TodayPlanningScreen.swift`, and `WeeklyScreen.swift`.
- Task timing and recovery: `TaskFocusSession.swift`, `TaskFocusControls.swift`, `TaskPlanning.swift`, `TaskPlanningEditor.swift`, `TaskEditorScreen.swift`, `AppState.swift`, `CaptureStore.swift`, `Domain.swift`, `CaptureRepository.swift`, and `DraftArchive.swift`.
- Content trail and export: `CaptureProvenance.swift`, `CaptureTrailView.swift`, `CaptureSourceView.swift`, `DayExport.swift`, `DailyArchive.swift`, and `ProjectFileArchive.swift`.
- Supporting styles/scoping: `SettingsScreen.swift`, `SearchScreen.swift`, `NewNoteScreen.swift`, `ScratchpadView.swift`, `WorkspaceQuery.swift`, and `WorkspaceStore.swift`.
- Regression coverage: four new suites (`TaskFocusTests`, `CaptureProvenanceTests`, `ProjectPickerTests`, `RedesignInteractionTests`), updated compatibility/layout suites, and the Open Design render branch in `NativeRenderTests.swift`.

Production screen renders use fictional isolated data with injected preferences and no user clipboard, external previews or notification delivery. Coverage includes 380×430 and 380×680 compact content, 1000×760 expanded content, light/dark appearances, project selection/creation, converted cards, Settings and weekly view. Native interaction evidence separately exercises actual controls and popovers. These renders are isolated native fixtures, not screenshots of personal user data. A second reviewer checked the final variants; no remaining material clipping or readability issue was identified. Popover window captures may omit compositor materials and are interaction evidence, not presentation mockups.

## Screens

- [Explorer before, 380×430](../explorer-2026-09-30/native-view-explorer-files-light-380x430.png)
- [Explorer after, 380×430](screenshots/native-view-redesign-explorer-light-380x430.png)
- [Expanded Explorer](screenshots/native-view-redesign-explorer-light-1000x760.png)
- [Inbox](screenshots/native-view-redesign-inbox-light-380x680.png)
- [Task details](screenshots/native-view-redesign-task-light-380x680.png)
- [Dark minimum-size Today](screenshots/native-view-redesign-today-dark-380x430.png)
- [Weekly view](screenshots/native-view-redesign-weekly-dark-760x680.png)

## Limits and release status

Paste destinations are user-recorded; copying or switching apps does not prove a paste. Missing application artwork uses a local fallback. Physical monitor disconnects, Spaces changes, VoiceOver speech, actual notification delivery, macOS permission revocation and distribution signing are not newly certified by these fixture tests. Relevant existing geometry, accessibility, permission-state and lifecycle regressions remain part of the full suite.

This is a local implementation and build. GitHub publication, notarization and TestFlight submission are separate from this change.
