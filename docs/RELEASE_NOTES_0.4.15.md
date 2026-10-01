# DaBin 0.4.15 (70) - preview-led collection cards

Collapsed Auto Capture hours and minimized imported-file batches now put their contents first: up to four preview tiles, prioritizing images and videos and using local thumbnails where available, occupy a large mosaic. A small `+N more` badge accounts for the remaining captures. The layout adapts from one image through a two-column pair, three-image hero layout and four-image grid. Weekly cards use a 152-point preview; normal cards use 220 points. Text, links and unsupported files retain readable titles and real content/type fallbacks.

The capture count and immutable saved date/time or capture-hour range sit directly beneath the preview. Automatic hours retain their original action counts separately when a save contains multiple captures; a type filter reports matching captures against the collection total. Captures promoted to tasks are shown individually and are not misreported as hidden collection contents. Clicking the overview expands the visible collection to show its saved items. Batch copy, notes, reminders, removal confirmation, saved batch minimize choices and hourly expand/collapse behavior remain available without an additional redundant expand button.

The mosaic reuses the bounded background thumbnail cache. It does not decode full originals on the main thread, create PDF/video players or fetch websites. Native board sizing now reserves the larger summary surface while preserving the screen-fitting limits.

## Verification and local deployment

**0.4.15 (70) is installed and running locally.** Its app and embedded helper match the frozen optimized ARM64 build receipt, and the installed bundle passes strict signature verification. Settings confirms the version. An actual hourly collection expands and collapses correctly in the installed app; the previous Inbox view was restored. Auto Capture remains paused and Show tooltips remains on. A normal quit preceded installation, and the previous 0.4.14 app was backed up. The guarded installer only replaces the app bundle; the personal archive was not independently byte-inventoried for this update.

All **21 selected Release suites** pass across two final reports: 20 existing regression suites and the new collection presentation suite. The latter passes **350 checks** covering bounded selection/layout, eight collapsed light/dark cards at 200/350-point widths, four expanded 650-point cards, native accessibility activation, persisted batch presentation and unchanged fictional capture/file data. These are actual 2× production-view renders using isolated fictional data, not screenshots of the private archive or an FPS benchmark. Earlier fixture-only compile/sampling failures were repaired without production changes or weaker containment checks. The source and build/QA inputs remain matched.

- [Local installation evidence and limitations](qa/local-install-0.4.15-2026-10-01/verification.json)
- [Actual light collection preview](../native/build/qa/collection-card-presentation/7413A04E-9F2B-4FDD-9B05-CC36F9343A97/hour-collapsed-350-light@2x.png)
- [Actual dark batch preview](../native/build/qa/collection-card-presentation/7413A04E-9F2B-4FDD-9B05-CC36F9343A97/batch-collapsed-350-dark@2x.png)
- [Native presentation report](../native/build/qa/collection-card-presentation/7413A04E-9F2B-4FDD-9B05-CC36F9343A97/collection-card-presentation-report.json)

No public release has occurred; public downloads remain 0.3.18. This is scoped verification, not a new full distribution/notarization review. The separate two-second-message request remains unidentified and is unchanged by this work.
