# DaBin QA cycle — 24 September 2026

## Matched compact icon rows — 0.3.13 (38)

DaBin 0.3.13 gives the primary actions and filters the same **280 × 34-point** row footprint. Every control now uses one 15-point SF Symbol in an 18-point canvas, a 40 × 34-point target and a 30-point circular selected or hover surface. The five primary actions distribute between the same outer edges as the six filters, preserving Add, Search, Export, Notifications and Settings in their existing order while removing the visible row stagger.

The exact optimized source passed **30/30 registered Release suites and 2,706 checks** with no source changes during the final run. The native header suite passed **31 checks**, including the shared-width geometry contract and real interaction at the redistributed action positions. The unlocked two-display regressions passed **214 general window**, **97 Weekly window** and **110 filter-resize** checks.

Fresh rendering produced **42 release interface views**. Retained original-resolution evidence covers empty and populated Daily at 1× and 2×, the 380-point narrow Weekly board and the representative 428-point two-day Weekly board in light and dark appearances. The inspected headers are centered, balanced and unclipped.

The optimized ARM64 direct build is **0.3.13 (38)** with production-source fingerprint `5f15ba6f71e53b59c8e99312c64654f4cab8edc7d6cfa012f87c2cdd9a07fa66`. Its executable is **5,794,496 bytes**, SHA-256 `a85a557812a41c7783bfe411c1a25f1ade6088de9969d0f09f96b5a307455314`. The verified update ZIP is **3,363,483 bytes**, SHA-256 `56f3474526ae6509971f0dec5357de665a719282a88bf1b75c30b57c12cebbbd`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

The one-page A4 PDF guide is unchanged and byte-identical at **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

The public GitHub release is live and marked latest. Its page and four assets returned HTTP 200 without authentication, and the downloaded ZIP, manifest, PDF guide and release notes were byte-identical to their recorded local sources. The installed 0.3.12 app then downloaded that public package and updated itself to 0.3.13 through Settings. The installed executable matches the verified production build; strict signatures, all 33 archive files, preferences, Desktop link and the verified 0.3.12 backup passed post-install checks. Live inspection confirmed the complete primary-action and filter order, accessible controls and preserved appearance/capture settings.

[0.3.13 evidence index](../docs/qa/0.3.13/README.md) · [Publication](../docs/qa/0.3.13/release-publication.json) · [Live installation](../docs/qa/0.3.13/live-install-v0.3.13.json) · [Full optimized run](../docs/qa/0.3.13/full-run/report.json) · [Release renders](../docs/qa/0.3.13/release-ui-renders.json) · [Build receipt](../docs/qa/0.3.13/build-receipt-v0.3.13.json) · [Update manifest](../docs/qa/0.3.13/update-manifest-v0.3.13.json) · [Static Store preflight](../docs/qa/0.3.13/app-store-preflight-static-v0.3.13.log) · [Release preflight](../docs/qa/0.3.13/app-store-preflight-release-v0.3.13.log).

## Weekly scoped Search and downloads — 0.3.12 (37)

DaBin 0.3.12 adds two explicit Search choices in Weekly: **Search Day** for a date selected from the displayed seven-day range and **Search Week** for the complete fixed range. Scoped Search keeps the active type filter, limits matches before adding the established immediate same-day context, labels the chosen scope and returns Back to Weekly. The date picker includes empty dates whose Weekly columns are hidden.

Weekly export now offers **Copy Day**, **Download Day**, **Copy Week** and **Download Week**. Day and week copy/download pairs share their exact deterministic UTF-8 documents. Export reads immutable stored capture days in chronological order, ignores active content filters, does not repeat task carryover projections, disables empty scopes independently and uses scope-specific success or failure feedback. The week filename is `DaBin-Week-YYYY-MM-DD-to-YYYY-MM-DD.txt`.

The exact optimized source passed **30/30 registered Release suites and 2,704 checks** with no source changes during the final run. Feature coverage includes **207 Domain**, **36 day/week export**, **28 export UI**, **138 Weekly state** and **29 native header interaction** checks. The unlocked two-display regressions passed **214 general window**, **97 Weekly window**, **110 filter resize**, **110 robot/drop** and **138 Daily capture** checks.

Fresh rendering produced **42 release interface views** and **62 broader native interface views**. Retained original-resolution evidence covers both Weekly action popovers at native Retina density, Search Day and Search Week results, the 380-point narrow Weekly board and the 428-point two-day board in light and dark appearances.

The optimized ARM64 direct build is **0.3.12 (37)** with production-source fingerprint `8bd0134c782ddbc2ee6989fe949e2c153acd71dad2f595fc8d7ddfe9e781ce30`. Its executable is **5,789,296 bytes**, SHA-256 `39fa0d88bf3a36bffbbe843e73f21e2ed6d398d7c5e312642203334b6f2692a2`. The verified update ZIP is **3,362,970 bytes**, SHA-256 `9c4956eb8c9a8273c94b1b6e8e00f48114fc202da28dccc31d5caf62410b0b1b`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

The one-page A4 PDF guide is unchanged and byte-identical at **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

The public GitHub release is live and marked latest. Its page and four assets returned HTTP 200 without authentication, and the downloaded ZIP, manifest, PDF guide and release notes were byte-identical to their verified local sources. The installed 0.3.11 app then downloaded that public package and updated itself to 0.3.12 through Settings. The installed executable matches the verified production build; strict signatures, the 29-file archive, preferences, Desktop link and verified 0.3.11 backup all passed post-install checks. Live inspection confirmed both Weekly scope menus and their independently enabled day/week actions.

[0.3.12 evidence index](../docs/qa/0.3.12/README.md) · [Publication](../docs/qa/0.3.12/release-publication.json) · [Live installation](../docs/qa/0.3.12/live-install-v0.3.12.json) · [Full optimized run](../docs/qa/0.3.12/full-run/report.json) · [Release renders](../docs/qa/0.3.12/release-ui-renders.json) · [Native renders](../docs/qa/0.3.12/native-view-renders.json) · [Build receipt](../docs/qa/0.3.12/build-receipt-v0.3.12.json) · [Update manifest](../docs/qa/0.3.12/update-manifest-v0.3.12.json) · [Static Store preflight](../docs/qa/0.3.12/app-store-preflight-static-v0.3.12.log) · [Release preflight](../docs/qa/0.3.12/app-store-preflight-release-v0.3.12.log).

## Playful camera-island capture confirmation — 0.3.11 (36)

DaBin 0.3.11 rebuilds the successful Auto Capture confirmation as a complete native camera-island performance. The robot peeks toward the capture, emerges from behind the physical island, performs one celebration and retreats fully behind the edge. Twelve reactions cover a wink, victory dance, double bounce, camera flash, card catch, clipboard hug, dizzy spin, wobbly salute, Saved stamp, confetti sneeze, screen high-five and sneak-and-grab. A shuffled deck excludes the previous three reactions; bounded gaze, timing and entrance variation keeps later performances alive without changing their 1.8–2.6 second budget.

Rapid captures reuse the active popup and update one `×N` badge without restarting or stacking robots. The panel cannot activate, become key, receive clicks or appear in screenshots. A built-in primary display attaches it to the camera island reported by macOS; a built-in display without an island uses the safe top center, and an external primary display uses the safe top right. The celebration starts only through the successful-save callback after durable archive work finishes. Partial and failed saves retain error feedback and do not celebrate. Reduce Motion replaces travel and spring effects with a static cropped peek, success checkmark and gentle 0.74-second fade. No audio was added.

The exact optimized source passed **30/30 registered Release suites and 2,559 checks** with no source changes during the final run. This includes **489 celebration-plan checks**, **36 presenter checks**, **41 Auto Capture service checks** and the complete existing storage, privacy, input, task, export, reminder, weekly, filter, window and update coverage.

Native robot QA passed **42 Retina renders**: all 12 celebration peaks on light and dark backgrounds, anticipation/entrance/reaction/exit phases, Reduce Motion confirmations and full production island popups with a rapid-capture `×3` badge. All 12 reactions produced distinct rasters. Active motion changed pixels, while Reduce Motion and hidden cleanup probes remained still. Fresh rendering also passed **34 release interface views** and **62 broader native interface views**. Original-resolution review covered the complete light/dark popup, reaction and phase contact sheets, reduced-motion checkmarks, and representative Daily and Weekly views.

The optimized ARM64 direct build is **0.3.11 (36)** with source fingerprint `397ec7f2133b857114262ca2a12020ff643f5fc983411d30bf1b152bb0fc8a22` and executable SHA-256 `0c735ddde9ef87c4a0ff464f0fd8dd6b2c967de582420c70ec52b3dafa6b4ad2`. The verified update ZIP is **3,314,777 bytes**, SHA-256 `81a691c6e5f9cfbfe82afe95f151a795b3e2737e678d4a01d8263ae4ccfc02ec`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

The one-page A4 PDF guide is unchanged and byte-identical at **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

Release [v0.3.11](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.11) is public and latest. Unauthenticated requests returned HTTP 200 for all four assets and the latest manifest; every downloaded asset was byte-identical to its verified local source.

The installed 0.3.10 app discovered, downloaded and installed the public 0.3.11 package through its own verified updater. The installed app, embedded helper and exact 0.3.10 backup pass strict signature checks. All **29 archive files** and the preferences file remain byte-identical, the Desktop link remains valid, and one ARM64 process is running. Live Settings inspection confirmed 0.3.11 (36), Auto Capture remains off, the existing Purple/dark/100%-opacity/camera-island preferences remain visible, and a follow-up check reports that 0.3.11 is current. DaBin was left on today's Daily view with All selected.

[0.3.11 evidence index](../docs/qa/0.3.11/README.md) · [Publication](../docs/qa/0.3.11/release-publication.json) · [Live installation](../docs/qa/0.3.11/live-install-v0.3.11.json) · [Full optimized run](../docs/qa/0.3.11/full-run/report.json) · [Robot render evidence](../docs/qa/0.3.11/robot-personality-renders.json) · [Release renders](../docs/qa/0.3.11/release-ui-renders.json) · [Native renders](../docs/qa/0.3.11/native-view-renders.json) · [Build receipt](../docs/qa/0.3.11/build-receipt-v0.3.11.json) · [Update manifest](../docs/qa/0.3.11/update-manifest-v0.3.11.json) · [Static Store preflight](../docs/qa/0.3.11/app-store-preflight-static-v0.3.11.log) · [Release preflight](../docs/qa/0.3.11/app-store-preflight-release-v0.3.11.log).

## Copy/paste Text filter — 0.3.10 (35)

DaBin 0.3.10 adds a dedicated Text filter immediately before Links. It includes only plain-text captures, whether copied, pasted or dragged, and excludes links, tasks and document files. The existing purple aligned-text symbol gives the icon a familiar visual match with text cards. Its tooltip and accessible name read **Copy/paste text**. Daily, contextual Search, Weekly and automatic hourly summaries use the same rule, while Weekly continues to keep every date with any recorded activity visible.

The exact optimized source passed **29/29 registered Release suites and 2,059 checks** with no source changes during the final run. New coverage verifies the exact six-filter order, text-only classification, contextual Search neighbors, hourly summary membership, full/sparse/empty Weekly behavior and native 380-point hit targets. All existing capture, task, export, reminder, Auto Capture, drag/paste, resizing and update suites remain passing.

Fresh rendering passed **34 release interface views** and **62 broader native interface views**. Original-resolution inspection covered the six centered icons in light and dark Daily at 380 points and Retina density, the selected Text state, the 428-point two-day Weekly view, and a 380-point constrained Weekly view. Text is immediately left of Links, every control remains evenly spaced, and the row neither clips nor wraps.

The optimized ARM64 direct build is **0.3.10 (35)** with source fingerprint `9d3a0f2ab06e2252760581e951bcf5fb8a0c35d15f7d9e9421a4c543047b2f8e` and executable SHA-256 `d2513dcb124068bf095d77118b9e6f3179c2ec9a7b3af04d32de0dad818c390b`. The verified update ZIP is **3,279,679 bytes**, SHA-256 `e1fa9fb3d741f5b705926cecef3374bab66f1ed65cb443ba033a178f8043b2eb`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

The one-page A4 PDF guide is unchanged and byte-identical at **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

Release [v0.3.10](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.10) is public and latest. Unauthenticated requests returned HTTP 200 for all four assets and the latest manifest; every downloaded asset was byte-identical to its verified local source.

The installed 0.3.9 app discovered, downloaded and installed the public 0.3.10 package through its own verified updater. The installed app, embedded helper and exact 0.3.9 backup pass strict signature checks. All **29 archive files** and the preferences file remain byte-identical, the Desktop link remains valid, and one ARM64 process is running. Live inspection confirmed the six-filter order and accessible Text label; on 23 September, Text showed one plain-text capture while All showed all four. A follow-up check reports that 0.3.10 is current. DaBin was left on today's Daily view with All selected.

[0.3.10 evidence index](../docs/qa/0.3.10/README.md) · [Publication](../docs/qa/0.3.10/release-publication.json) · [Live installation](../docs/qa/0.3.10/live-install-v0.3.10.json) · [Full optimized run](../docs/qa/0.3.10/full-run/report.json) · [Release renders](../docs/qa/0.3.10/release-ui-renders.json) · [Native renders](../docs/qa/0.3.10/native-view-renders.json) · [Build receipt](../docs/qa/0.3.10/build-receipt-v0.3.10.json) · [Update manifest](../docs/qa/0.3.10/update-manifest-v0.3.10.json) · [Static Store preflight](../docs/qa/0.3.10/app-store-preflight-static-v0.3.10.log) · [Release preflight](../docs/qa/0.3.10/app-store-preflight-release-v0.3.10.log).

## Active-date Weekly view — 0.3.9 (34)

DaBin 0.3.9 keeps the seven-date calendar range for navigation while rendering only dates that contain captures or tasks. Carried and reminder-day tasks count as activity. Filters remain independent of date visibility, so changing a content filter does not rearrange the week. The floating panel now sizes itself from zero through seven active dates; a completely empty range stays at the compact 380 × 290 point size and shows one bored-robot message instead of seven empty columns.

The exact optimized source passed **29/29 registered Release suites and 2,132 checks** with no source changes during the final run. Focused coverage includes **118 Weekly state checks** and **95 native Weekly window checks**. These verify empty and sparse ranges, nonconsecutive dates, carried and reminder-day tasks, filter stability, every active-date width, both unfolding directions, screen clamping, range navigation, detail return and compact restoration.

Fresh rendering passed **34 production interface views** and **6 focused compact empty Daily/Weekly views**. Original-resolution inspection covered 380 × 290 point empty weeks and 428-point two-day weeks in light and dark appearances, plus a 380-point constrained sparse-week layout. Empty dates have no date heading or card, remaining dates retain chronological order, and the header remains fully usable.

The optimized ARM64 direct build is **0.3.9 (34)** with source fingerprint `07a81ba16f933d992e95ca80d105409375557e6495d05bebaa53787834025d84` and executable SHA-256 `afcc90d51fce5e5768247ac8606acfe32184e4d5b4537feefe6fe7a0ef8fdc01`. The verified update ZIP is **3,279,344 bytes**, SHA-256 `e653928f65287cbb48ada20316d90cfab169483b0b7074317fb50fd0909890e6`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

Release [v0.3.9](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.9) is public and latest. Unauthenticated requests returned HTTP 200 for the repository, release, all four assets and latest manifest; every downloaded asset was byte-identical to its verified local source.

The installed 0.3.8 app discovered, downloaded and installed the public 0.3.9 package through its own verified updater. The installed app and helper pass strict signature checks, the exact prior 0.3.8 app is backed up, the Desktop link remains valid, one ARM64 process is running, and a subsequent check reports that 0.3.9 is current. All **29 archive files** and the preferences file remain byte-identical.

Live Weekly verification used the existing archive without editing it. In the 18–24 September range, only Tuesday 22 and Wednesday 23 rendered, the five empty dates were absent, the footer read **2 active days**, and the panel measured **428 × 560** points. The empty 11–17 September range rendered no date headings, showed the single bored-robot empty state, and measured **380 × 290** points. DaBin was left on the current two-day Weekly view.

[0.3.9 evidence index](../docs/qa/0.3.9/README.md) · [Publication](../docs/qa/0.3.9/release-publication.json) · [Live installation](../docs/qa/0.3.9/live-install-v0.3.9.json) · [Full optimized run](../docs/qa/0.3.9/full-run/report.json) · [Release renders](../docs/qa/0.3.9/release-ui-renders.json) · [Empty Weekly renders](../docs/qa/0.3.9/weekly-entry-renders.json) · [Build receipt](../docs/qa/0.3.9/build-receipt-v0.3.9.json) · [Update manifest](../docs/qa/0.3.9/update-manifest-v0.3.9.json) · [Static Store preflight](../docs/qa/0.3.9/app-store-preflight-static-v0.3.9.log) · [Release preflight](../docs/qa/0.3.9/app-store-preflight-release-v0.3.9.log).

## Day Export and compact header — 0.3.8 (33)

DaBin 0.3.8 adds **Export Day** between Search and Notifications in the centered primary-action row. Its anchored action popover exports every stored action for the selected calendar date, independent of the active content filter, in chronological plain text. **Copy Day** and **Export Text File** use the same UTF-8 document; empty days disable both actions, while success, cancellation and failure remain distinct. The export UI and real-window header suites cover presentation state, keyboard shortcuts, Escape dismissal, accessible labels and native placement beneath the icon. Outside-click dismissal uses the native transient popover behavior plus a board-window event monitor and is reserved for the installed-app check.

The Daily and Weekly headers now use three compact rows: logo/date navigation/mode/neutral close control, primary actions, then filters. Add, Search, Export Day, Notifications and the Settings wheel share the existing coloured icon language, hover, pressed and keyboard-focus treatment. The action and filter rows share one center axis, and the narrow 380-point Daily layout retains every control without clipping or the former vertical dead area.

The exact optimized source passed **29/29 registered Release suites and 2,102 checks** with no source changes during the run. Focused coverage includes **24 Day Export checks**, **22 Day Export UI checks** and **18 live header-interaction checks**. Broader regression coverage retained **214 general window checks across two displays**, **78 Weekly window checks**, **110 filter-resize checks**, **110 robot/drop checks** and **138 Daily-capture checks**.

Fresh rendering passed **34 production interface views**. Original-resolution inspection covered compact Daily at 380 points and Weekly at 900 points in light and dark appearances, including native 2× Daily samples. The three-row hierarchy, centered alignment, coloured export/settings actions, neutral close control and narrow-layout fit passed visual review.

The optimized ARM64 direct build is **0.3.8 (33)** with source fingerprint `b286601bf9262b09651661655e03b455a28832cd2996dc25827160af535f648c` and executable SHA-256 `49afd0e82795639d967511bdd74296262e6a169b05ebaf6e6270eb234b10516d`. The verified update ZIP is **3,270,792 bytes**, SHA-256 `d4700284846007251d75f033d4dcfb578bf221c85fb90282a497be9ae150ffef`. Packaging passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

The refreshed one-page A4 guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. Its tracked and output copies are byte-identical and passed one-page geometry, text extraction, boundary and visual inspection.

Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode.

Release [v0.3.8](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.8) is public and latest. Unauthenticated requests returned HTTP 200 for the repository, release, all four assets and the latest manifest; every downloaded asset was byte-identical to the verified local release.

The installed 0.3.7 app discovered, downloaded and installed the public 0.3.8 package through its own verified updater. The installed app and embedded helper pass strict signature checks, the exact prior 0.3.7 app is backed up, the Desktop link remains valid, one ARM64 DaBin process is running, and a subsequent check reports that 0.3.8 is current. All **29 archive files** and the preferences file remain byte-identical. Live inspection confirmed the three compact header rows, required action order and accessible names, disabled empty-day export state, physical click-away dismissal, the Settings gear menu and Settings navigation.

[0.3.8 evidence index](../docs/qa/0.3.8/README.md) · [Publication](../docs/qa/0.3.8/release-publication.json) · [Live installation](../docs/qa/0.3.8/live-install-v0.3.8.json) · [Full optimized run](../docs/qa/0.3.8/full-run/report.json) · [Release renders](../docs/qa/0.3.8/release-ui-renders.json) · [Build receipt](../docs/qa/0.3.8/build-receipt-v0.3.8.json) · [Update manifest](../docs/qa/0.3.8/update-manifest-v0.3.8.json) · [Quick-guide layout check](../docs/qa/0.3.8/quick-guide-layout-check.json) · [Static Store preflight](../docs/qa/0.3.8/app-store-preflight-static-v0.3.8.log) · [Release preflight](../docs/qa/0.3.8/app-store-preflight-release-v0.3.8.log).

## Settings wheel — 0.3.7 (32)

The Daily and Weekly header menu now uses the outline `gearshape` SF Symbol instead of the three-dot ellipsis. Its 13-point size, 30 × 30-point target and muted colour match the adjacent task, search and reminder controls. The menu behavior is unchanged, and its help and accessibility label now read **Settings and options**.

The exact optimized source passed **26/26 registered Release suites and 2,038 checks** with no source changes during the run. This includes application lifecycle and update configuration coverage, **214 general window checks across two displays**, **78 Weekly window checks**, **110 filter-resize checks**, **110 robot/drop checks** and **138 Daily-capture checks**.

Fresh rendering passed **34 production interface views**. Original-resolution inspection covered the compact Daily header at native 2× density and the 900-point Weekly header in light and dark appearances. The wheel remains crisp, evenly spaced and visually aligned with the surrounding outline icons.

The optimized ARM64 direct build is **0.3.7 (32)** with source fingerprint `a2fde0f178bfc50ebc7fa2c03788908b437225dadd8f0c0c3cbb5eec3ac5990a` and executable SHA-256 `e02c499b89cfb5b85e720954843e366739e8eb1616362f2bffaaf7bd3ac499db`. The verified update ZIP is **3,198,381 bytes**, SHA-256 `1a4154cabbc8f8fc9acba9e68a816ef79693f973d9fc21e424e7db2088f5b40a`. Packaging passed isolated fresh install, replacement, backup, signature, extraction, manifest round trip and exact executable identity.

Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode. No Store archive or upload was performed.

Release [v0.3.7](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.7) is public and latest. Unauthenticated requests returned HTTP 200 for the repository, release, four assets and latest manifest; every expected asset was byte-identical to the verified local release. The installed 0.3.6 app then discovered, downloaded and installed the public 0.3.7 package through the native updater. The final app and helper pass strict signature checks, one ARM64 DaBin process is running, the exact 0.3.6 app is backed up, the Desktop link is intact, and a subsequent update check reports that 0.3.7 is current.

Live inspection confirmed the outline wheel, its **Settings and options** accessibility label, the menu opening, and the Settings command reaching the Settings screen. All **29 existing archive files** and the preferences file remained byte-identical, so the visual-only update required no migration and preserved the existing appearance, link-preview, robot-placement and default-off Auto Capture settings.

[0.3.7 evidence index](../docs/qa/0.3.7/README.md) · [Publication](../docs/qa/0.3.7/release-publication.json) · [Live installation](../docs/qa/0.3.7/live-install-v0.3.7.json) · [Full optimized run](../docs/qa/0.3.7/full-run/report.json) · [Release renders](../docs/qa/0.3.7/release-ui-renders.json) · [Build receipt](../docs/qa/0.3.7/build-receipt-v0.3.7.json) · [Update manifest](../docs/qa/0.3.7/update-manifest-v0.3.7.json) · [Static Store preflight](../docs/qa/0.3.7/app-store-preflight-static-v0.3.7.log).

## Rounded caption cards — 0.3.6 (31)

Every top-level individual caption in Daily, Search and Reminders now uses a lightly filled continuous rounded rectangle with a thin 0.75-point neutral outline. Carried tasks retain their stronger 1-point theme-colour frame. Rows inside expanded automatic-hour actions omit the inner outline because the action container already provides the rounded card boundary. The compact panel-height calculation reserves the new inter-card spacing and enough room for a minimized task's complete rounded edge and controls above the footer.

The exact optimized source passed **26/26 registered Release suites and 2,038 checks** with no source changes during the run. Relevant coverage includes **30 capture-action checks**, **110 filter-resize checks**, **138 Daily-capture checks**, **214 general window checks across two displays**, Weekly window/state coverage, and the unchanged storage, input, Auto Capture and update suites.

Fresh rendering passed **34 production interface views**. Original-resolution inspection covered ordinary framed captions, carried tasks, minimized cards and expanded automatic actions in light and dark appearances. Dedicated native 2× Search renders confirm the 0.75-point outline stays continuous and legible at Retina density without clipping content or creating a duplicate frame inside hourly actions.

The optimized ARM64 direct build is **0.3.6 (31)** with source fingerprint `783f074b0a0c5ba52378ffc1ad07aeb69228864d05f03b23e77119c5a4084e3c` and executable SHA-256 `054497fee397658bfd54ef76e77440a5320a2c05a426ce725dc890a42a4db2e6`. The verified update ZIP is **3,197,313 bytes**, SHA-256 `1f6f5c49bc6dd6c3466c8d94debc07da776297edcf45c9257fcc8b12f41e5b80`. Packaging passed isolated fresh install, replacement, backup, signature, extraction, manifest round trip and exact executable identity.

Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode. No Store archive or upload was performed.

Release [v0.3.6](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.6) is public and latest. Unauthenticated requests returned HTTP 200 for the repository, release, four assets and latest manifest; every expected asset was byte-identical to the verified local release. The installed 0.3.5 app then discovered, downloaded and installed the public 0.3.6 package through the native updater. The final app and helper pass strict signature checks, one ARM64 DaBin process is running, the exact 0.3.5 app is backed up, the Desktop link is intact, and a subsequent update check reports that 0.3.6 is current. Live Daily inspection showed the new thin rounded card frame.

All **29 existing archive files** and the preferences file remained byte-identical. The visual-only update required no archive migration and preserved the existing dark mode, opacity, theme, link-preview, robot-placement and default-off Auto Capture settings.

[0.3.6 evidence index](../docs/qa/0.3.6/README.md) · [Publication](../docs/qa/0.3.6/release-publication.json) · [Live installation](../docs/qa/0.3.6/live-install-v0.3.6.json) · [Full optimized run](../docs/qa/0.3.6/full-run/report.json) · [Release renders](../docs/qa/0.3.6/release-ui-renders.json) · [Build receipt](../docs/qa/0.3.6/build-receipt-v0.3.6.json) · [Update manifest](../docs/qa/0.3.6/update-manifest-v0.3.6.json) · [Static Store preflight](../docs/qa/0.3.6/app-store-preflight-static-v0.3.6.log).

## Auto Capture — 0.3.5 (30)

DaBin 0.3.5 adds the default-off **Auto Capture** setting under Settings → Capture. It monitors only future clipboard changes and new images in a user-authorized screenshot folder, retains native Finder transfer grants for copied files, stores best-effort source-application metadata, excludes DaBin and common password managers by default, and stops pending work immediately when paused or disabled. Automatic links never request website previews. The first-enable explanation describes local-only storage and the editable exclusions list.

The fourth successfully recorded automatic action in a fixed local clock hour becomes one expandable Daily summary. A stable outer identity preserves the feed anchor across expand/collapse, the count updates from durable records, previous-day summaries include their date, and the minus control has the exact accessibility label **Collapse actions**. Successful complete actions alone trigger the reused, click-through robot panel on the hardware primary display; partial and failed actions do not. The panel stays inside safe display geometry, does not become key or main, is excluded from screen capture, combines burst counts and follows Reduce Motion.

The exact optimized source passed **26/26 registered Release suites and 2,038 checks**. Focused coverage includes **41 Auto Capture service checks**, **116 clipboard/file intake checks**, **25 hourly-grouping checks**, **25 confirmation-presenter checks**, **105 weekly-state checks**, **214 general window checks across two real displays**, **110 filter-resize checks**, **110 robot/drop checks** and **138 Daily-capture checks**. Tests verify default-off state, no startup import, immediate Pause/Off cancellation, missing/revoked folder access, excluded-app transitions, activity-time screenshot attribution, opposite-channel image deduplication, full file-write/decode settling, PDF exclusion, Finder sandbox-grant retention, multi-file grouping and success-only confirmation.

Fresh rendering passed **32 production board views**. Original-resolution review covered Auto Capture Settings and collapsed/expanded hourly groups in light and dark appearances, including native 2× Settings samples. The refreshed one-page A4 guide passed extraction, bounds and visual checks; its tracked, packaged and standalone copies are byte-identical.

The optimized ARM64 direct build is **0.3.5 (30)** with source fingerprint `098cfbd3fcc749bce73265e644f92aa48000f789da501b21590eb148d57f7f72` and executable SHA-256 `70ffc44111382fbf9cf63a4e2a22383783681b45e61d8e63dc320f0a2b1230a9`. The verified update ZIP is **3,197,682 bytes**, SHA-256 `9b283809330946d3ff58faeab30258502e6478717f80c6c417c36d1fcdfbd5cd`. Packaging passed isolated fresh install, replacement, backup, signature, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.

Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode. The selected screenshot-folder monitor treats each new image in that folder as a screenshot, so the UI and guide recommend a dedicated screenshot folder; source attribution remains best effort. No Store archive or upload was performed.

Release [v0.3.5](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.5) is public and latest. Unauthenticated requests returned HTTP 200 for the repository, release, four assets and latest manifest; every expected asset was byte-identical to the verified local release. The installed 0.3.4 app then discovered, downloaded and installed the public 0.3.5 package through the native updater. The final app and helper pass strict signature checks, one ARM64 DaBin process is running, the exact 0.3.4 app is backed up, the Desktop link is intact, and a subsequent update check reports that 0.3.5 is current. Live Settings verification shows the exact Auto Capture description with the switch off and the default-exclusion explanation.

All eight existing user payload files remained byte-identical. First launch deterministically regenerated 21 generated sidecars for seven captures to add schema-4 capture-origin metadata. Removing the new manual-origin field and Markdown line reconstructed all prior JSON and Markdown hashes exactly; no user payload or capture ID changed. Existing visible appearance, link-preview and robot-placement preferences were also preserved, while the new Auto Capture status was persisted as disabled.

[0.3.5 evidence index](../docs/qa/0.3.5/README.md) · [Publication](../docs/qa/0.3.5/release-publication.json) · [Live installation](../docs/qa/0.3.5/live-install-v0.3.5.json) · [Full optimized run](../docs/qa/0.3.5/full-run/report.json) · [Release renders](../docs/qa/0.3.5/release-ui-renders.json) · [Build receipt](../docs/qa/0.3.5/build-receipt-v0.3.5.json) · [Update manifest](../docs/qa/0.3.5/update-manifest-v0.3.5.json) · [Static Store preflight](../docs/qa/0.3.5/app-store-preflight-static-v0.3.5.log).

## Daily / Weekly toggle and sandboxed updater — 0.3.4 (29)

DaBin 0.3.4 carries forward the compact native **Daily / Weekly** segmented control and supersedes 0.3.3. Daily → Weekly opens seven days ending on the selected date. Weekly → Daily preserves the selected date, type filter, Daily scroll target and unsaved drafts. The centered date, weekly day headings, Back navigation, directional panel transition and Reduce Motion behavior remain available.

Live installation QA for 0.3.3 exposed that macOS ignores `NSWorkspace.OpenConfiguration.arguments` from a sandboxed caller. The failure happened before replacement and left the installed app and archive unchanged. The 0.3.4 app now opens a private, one-use `.dabinupdate` document with its helper. The handoff constrains the verified ZIP to DaBin's own Updates directory and validates its schema, owner, permissions, name, location and SHA-256. The helper independently rechecks the ZIP, extracted layout, ARM64 app and signature before confirmation. Exact LaunchServices document delivery passed package QA against the extracted release helper.

The final optimized source passed **23/23 registered suites and 1,932 checks**. Update coverage increased to **29 service checks** and **12 channel/configuration checks**; weekly coverage retained **103 state checks**, **78 live window checks**, **110 filter-resize checks** and **214 general window checks across two real displays**. Fresh release rendering passed **28 production board views**, **10 direct native robot artifacts** and **8 empty Daily/Weekly views** in light and dark appearances. Original-resolution inspection covered Daily at 380 points and Weekly at 800, 900 and 1,440 points without selector, date, range or navigation overlap.

The optimized ARM64 direct build is **0.3.4 (29)** with source fingerprint `52798f6254f2b08f47049508e1a924848adf474f0e29af5c01be74ab30b80152` and executable SHA-256 `fbe81f1c063795112596e43a4ddcb7d187d51903a8d87d3177f15c2ddd66ea99`. The verified update ZIP is **2,984,144 bytes**, SHA-256 `6945e85bc95709771b3077bbadbab2af9f2d16a43aa4a8d25ab9ebf66192fa40`. Packaging passed isolated fresh install, replacement, backup, signature, extraction, manifest round trip and the sandbox-compatible document handoff. The included one-page guide remains byte-identical to the visually approved repository PDF.

The patched 0.3.3 bridge was installed over 0.3.2 to enable a true in-app rehearsal. It retained the Desktop link, produced one running DaBin process, and left all **29 archive files** byte-for-byte unchanged. Static Store packaging passed **20/20** checks. App Store release preflight retains two external prerequisites: an Apple Developer Team ID and full Xcode. No Store archive or upload was performed.

Release [v0.3.4](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.4) is public and latest. Independent unauthenticated requests returned HTTP 200 for the repository, release, four assets and latest manifest; every expected asset was byte-identical to the verified local release. The installed 0.3.3 bridge then found, downloaded and installed the public 0.3.4 package through the native document handoff. The final app and helper pass strict signature checks, one DaBin process is running, the exact 0.3.3 bridge is backed up, preferences and the Desktop link remain intact, no handoff file remains, and all 29 archive files are still byte-for-byte unchanged. Live Daily → Weekly → Daily interaction and the final “up to date” state passed.

[0.3.4 evidence index](../docs/qa/0.3.4/README.md) · [Publication](../docs/qa/0.3.4/release-publication.json) · [Live installation](../docs/qa/0.3.4/live-install-v0.3.4.json) · [Full optimized run](../docs/qa/0.3.4/full-run/report.json) · [Release renders](../docs/qa/0.3.4/release-ui-renders.json) · [Empty Daily/Weekly renders](../docs/qa/0.3.4/weekly-entry-renders.json) · [Build receipt](../docs/qa/0.3.4/build-receipt-v0.3.4.json) · [Update manifest](../docs/qa/0.3.4/update-manifest-v0.3.4.json).

## Daily / Weekly toggle — 0.3.3 (28)

DaBin 0.3.3 replaces the separate Today and This Week actions with one native segmented control labeled **Daily** and **Weekly**. Daily → Weekly opens seven days ending on the selected date. Weekly → Daily changes only the presentation route, preserving the selected date, type filter, Daily scroll target and unsaved drafts. The centered date, weekly day headings, Back navigation, directional panel transition and Reduce Motion behavior remain available.

The final optimized source passed **23/23 registered suites and 1,923 checks**. The updated weekly coverage includes **103 state checks**, **78 live window checks**, **110 filter-resize checks** and **214 general window checks across two real displays**. The release renderer passed **28 production board views**, **10 direct native robot artifacts** and **8 additional empty Daily/Weekly views**. Original-resolution inspection covered Daily at 380 points and Weekly at 800, 900 and 1,440 points in light and dark appearances; the toggle labels, selected state, centered date/range and navigation remained readable without overlap.

The optimized ARM64 direct build is **0.3.3 (28)** with source fingerprint `5e265bbda90bc9f4f7d82e5e2fb1a4cbb4134e61ab719abc7f7bd7379a9a3af9` and executable SHA-256 `23bac4cf61a4f960198edc1e04fd41490aef843c99dce9ac0a69018dfe677411`. The verified update ZIP is **2,942,317 bytes**, SHA-256 `36048bd1248c2cfd2593ef2282c121cf2e4d76edbb1a9f3ab7349def6599ce23`. Packaging passed isolated fresh install, replacement, backup, signature, extraction and downloaded-package checks. Its one-page A4 guide passed text extraction, bounds checks and full-page visual inspection; the bundled and repository copies are byte-identical.

Static Store packaging passed **20/20** checks. App Store release preflight retains the same two external prerequisites: an Apple Developer Team ID and full Xcode. No archive or Store upload was performed.

[0.3.3 evidence index](../docs/qa/0.3.3/README.md) · [Full optimized run](../docs/qa/0.3.3/full-run/report.json) · [Release renders](../docs/qa/0.3.3/release-ui-renders.json) · [Empty Daily/Weekly renders](../docs/qa/0.3.3/weekly-entry-renders.json) · [Build receipt](../docs/qa/0.3.3/build-receipt-v0.3.3.json) · [Update manifest](../docs/qa/0.3.3/update-manifest-v0.3.3.json).

## Updater handoff hotfix — 0.3.2 (27)

DaBin 0.3.2 preserves the complete camera-island placement and robot-personality work from 0.3.1 and fixes the direct updater handoff. A live update rehearsal from the installed 0.3.0 app exposed that LaunchServices could reuse an existing updater-helper instance and omit the verified ZIP path and SHA-256 command-line arguments. The failure occurred before confirmation or replacement. Setting `NSWorkspace.OpenConfiguration.createsNewApplicationInstance` to `true` made the exact package arguments appear in the helper process and produced the correct native confirmation for 0.3.1; that rehearsal was cancelled before installation. The helper now also includes the underlying localized error in its failure alert.

The final optimized 0.3.2 source passed **23/23 registered suites and 1,917 checks**. Separate local PDF, RTF and H.264 processing passed **39/39**, for **1,956 automated checks**. Update coverage includes **21 service checks** and **11 channel/configuration checks**, including the fresh-instance requirement and argument preservation. The release renderer passed **28 production board views** and **10 direct native 2× robot artifacts**. Its timed digest samples changed 45,620 raster bytes; Reduce Motion and hidden-character cleanup remained visually stable with no background animation work.

The optimized ARM64 direct build is **0.3.2 (27)** with source fingerprint `9cfa700e92720b2beda2c67e972c625f4ee5bb2d14ac01bca5ede19f4ea4c1e3` and executable SHA-256 `f95a3805ea5bf28f63afb529571a09546ce855e5ae1fa2b7ea78e19f87bfa00f`. The verified update ZIP is **2,940,064 bytes**, SHA-256 `6ced075743d2af5497d94711071d34fed85b3fc6a36bc7f7c9699281e22131a3`; its bundled PDF is byte-identical to the standalone guide. Packaging exercised the exact helper through isolated fresh install, replacement, backup, extracted-package verification and embedded-helper download modes.

Release [v0.3.2](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.2) is public and latest. Independent unauthenticated requests returned HTTP 200 for the repository, release, manifest, ZIP, guide and release notes; every downloaded asset matched the local release bytes. The verified helper installed 0.3.2 over 0.3.0, preserved a strictly valid backup, retained the Desktop link and camera-island preference, and left the logical capture records and every capture payload byte unchanged. The installed app reports “You’re up to date with DaBin 0.3.2.”

The installed robot was also exercised live at the built-in camera island. Its 72 × 88-point window appeared at Quartz coordinates x 3279, y 36, centered below the reported 185-point gap. Left/right pointer samples changed 257 decoded raster bytes, and moving away removed the window after the retreat interval.

Static Store packaging passed **20/20** checks. App Store release preflight retains the same two environment/owner blockers: an Apple Developer Team ID and full Xcode. The direct build is locally ad-hoc signed for this Mac; general distribution still needs Developer ID signing and notarization.

[0.3.2 evidence index](../docs/qa/0.3.2/README.md) · [Publication and installation](../docs/qa/0.3.2/release-publication.json) · [Live updater handoff](../docs/qa/0.3.2/updater-handoff-live.json) · [Live camera-island check](../docs/qa/0.3.2/live-camera-island-v0.3.2.json) · [Full optimized run](../docs/qa/0.3.2/full-run/report.json) · [Media integration](../docs/qa/0.3.2/media-integration-v0.3.2.log) · [Release renders](../docs/qa/0.3.2/release-ui-renders.json) · [Robot personality QA](../docs/qa/0.3.2/robot-personality-renders.json) · [Build receipt](../docs/qa/0.3.2/build-receipt-v0.3.2.json) · [Update manifest](../docs/qa/0.3.2/update-manifest-v0.3.2.json).

## Camera-island home and robot personality — 0.3.1 (26)

Settings now offers **Screen corners** and **Below camera island** under **Your quiet corner**. The second mode derives the physical cutout from `NSScreen.safeAreaInsets` and the two auxiliary top regions instead of using a model list or display name. On the built-in screen used for live verification, macOS reported a 32-point top safe area and a 185-point center gap; the 72 × 88-point robot appeared centered directly below it. The external display reported no cutout geometry and retained corner reveal under the same preference. Changing the setting hid the previous target cleanly, and moving the pointer away stopped the character and removed its window.

The transient robot is now a native layered character with independent shell, lid, face, eyes, mouth, arms, intake card and shadow. It springs in from the selected edge, follows the pointer, waves on first hover, opens for an accepted drag, chews while saving, celebrates success, shrugs for a partial save and tilts after failure. Quiet idle blinks, glances and shrugs run only while visible. The macOS Reduce Motion setting preserves instant expressions while removing travel, repeated and keyframed movement.

The exact optimized source passed **23/23 registered suites and 1,916 checks**. New coverage includes **170 preference checks**, **214 window checks across both attached displays**, **110 robot/drop checks** and **40 motion-state checks**. It exercises real safe-area geometry, synthetic positive/negative display coordinates, no-island fallback, live preference changes, reveal priority, drag/save/result priority, all three entrance directions, pointer clamping, ambient cancellation and Reduce Motion. Separate local PDF, RTF and H.264 processing passed **39/39** checks, for **1,955 automated checks** in the release cycle.

The release renderer passed **28 production board views** plus **10 direct native 2× robot artifacts**. The seven settled personality states have distinct rasters. Two live digest samples changed 45,590 raster bytes as the card entered and the robot blinked; Reduce Motion changed zero bytes over half a second, and a stopped hidden robot changed zero bytes over 0.4 seconds. Light and dark Settings-bottom renders show the complete Robot home control at the compact 380 × 430-point board size. The one-page A4 guide passed extraction, bounds checks and full-page visual inspection.

The optimized ARM64 direct build is **0.3.1 (26)** with source fingerprint `7a7bd9aafd0c3b4c3f96bb964dd7e45cf5d472a504d33b6603d950e360e17c0c` and executable SHA-256 `eb77529d11036b42264e1f29612940fa4a5ca04a37f55032dbf812fac803b5a5`. The verified update ZIP is **2,939,852 bytes**, SHA-256 `bc2d8893e38cfd0c1a9cae0889bef3b6400a4a9e3b88ac705631391fd8975c31`; its PDF is byte-identical to the standalone guide. Packaging exercised the exact helper through isolated fresh install, replacement, backup and downloaded-package modes.

Static Store packaging passed **20/20** checks. App Store release preflight retains **two environment/owner blockers**: the Apple Developer Team ID and full Xcode. Store distribution signing, archive validation, App Store Connect metadata and Apple review remain external. The local direct build is ad-hoc signed for this Mac; distribution to other Macs still needs Developer ID signing and notarization.

[Full optimized run](../docs/qa/0.3.1/full-run/report.json) · [Media integration](../docs/qa/0.3.1/media-integration-v0.3.1.log) · [Release renders](../docs/qa/0.3.1/release-ui-renders.json) · [Robot personality QA](../docs/qa/0.3.1/robot-personality-renders.json) · [Live camera-island check](../docs/qa/0.3.1/live-camera-island-v0.3.1.json) · [Static Store preflight](../docs/qa/0.3.1/app-store-preflight-static-v0.3.1.log) · [Release preflight](../docs/qa/0.3.1/app-store-preflight-release-v0.3.1.log).

## GitHub update channel — 0.3.0 (25)

The complete source and documentation are published at [github.com/RoeyAsterix/DaBin](https://github.com/RoeyAsterix/DaBin). Release [v0.3.0](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.0) contains the verified update ZIP, public update manifest and one-page PDF guide. Independent unauthenticated checks returned HTTP 200 for the repository, release, manifest, ZIP and PDF; the downloaded ZIP size and SHA-256 matched the manifest exactly. DaBin 0.3.0 (25) is installed at `~/Applications/DaBin.app`, the previous app is preserved, the Desktop shortcut is valid, and the in-app live check reports “You’re up to date with DaBin 0.3.0.” The capture archive was not modified.

DaBin now has a user-initiated direct update flow in **Settings → Software updates** and the native app menu. The app reads only the fixed `RoeyAsterix/DaBin` GitHub Release manifest, follows HTTPS redirects only to GitHub release hosts, validates the manifest schema, bundle, numeric version/build, Apple Silicon and macOS requirements, exact release path, byte count and SHA-256, then opens its embedded signed helper. The helper independently rechecks the ZIP checksum, rejects symbolic links and unexpected layouts, validates the ARM64 Release app and strict signature, asks before updating, preserves a verified backup, rolls back on failure and leaves the capture archive untouched. It never checks or downloads silently.

The generated Xcode Store configuration does not define `DABIN_DIRECT_UPDATES`, contains no direct feed key and does not embed the helper. Its Settings screen reports that updates are delivered through the Mac App Store. The standalone builder alone enables the GitHub channel. The current ad-hoc package is for this Mac; broad direct distribution still needs stable Developer ID signing and Apple notarization.

The exact optimized source passed **22/22 registered suites and 1,859 checks**. This includes **21 no-network software-update checks**, **10 channel-boundary checks**, **25 privacy checks**, menu/composition ownership, checksum rejection, fixed-origin rejection, no automatic network request, and the complete existing storage/input/window suite. The run found and fixed a two-display edge case: releasing the board below a non-main display could select the other display as a fallback. The final window resize run keeps the board on its active display and clamps the whole panel on screen.

Separate synthetic PDF, RTF and H.264 processing passed **39/39** checks. **28 production-view release renders** passed in light and dark, including the Software updates section, grouped imports, compact empty view, Daily, Week, Search, Detail, tasks, Settings and native 2× samples. The refreshed one-page PDF passed extraction, one-page A4 geometry, boundary checks and visual inspection.

The optimized direct build is **0.3.0 (25)** with source fingerprint `2a81ade40c1f47a608216bdc4e29e1a2af4bb552152f9139e7ea94a1ba96ab86` and executable SHA-256 `69ce68583abbe2fa702be6b17e7039d072c90eeb27bb4311da744c46c7eeedc7`. The final update asset is **2,895,714 bytes**, SHA-256 `d85be187dc910be4436f20c349595fd0d0d9d9093d6089d415b9be49753b0cbb`. Packaging exercised the exact helper through fresh install, replacement, backup and downloaded-package modes at isolated destinations.

Static Store packaging passed **20/20** checks. Release preflight now has **two environment/owner blockers**: the Apple Developer Team ID and full Xcode. The configured GitHub privacy/support URLs pass the offline URL gate; Store signing, archive validation, App Store Connect metadata and Apple review remain external.

[Public release verification](../docs/qa/0.3.0/release-publication.json) · [Full optimized run](../docs/qa/0.3.0/full-run/report.json) · [Media integration](../docs/qa/0.3.0/media-integration-v0.3.0.log) · [Release render manifest](../docs/qa/0.3.0/release-ui-renders.json) · [Static Store preflight](../docs/qa/0.3.0/app-store-preflight-static-v0.3.0.log) · [Release preflight](../docs/qa/0.3.0/app-store-preflight-release-v0.3.0.log).

## Appearance controls and grouped imports — 0.2.2 (24)

Settings now has a persistent **Dark mode** switch and a **Transparency** slider from 35% to 100% board opacity, with the existing 75% value as the default. Light and dark mode are explicit app preferences and update the open board immediately. Malformed or non-finite saved appearance values fall back safely without touching capture data.

Files supplied by one explicit paste or drop now appear under one compact caption card in Daily and Week. Every original remains an independent verified archive record and can be opened separately. The shared card exposes one Comment, Reminder, minimize/expand and confirmed batch-removal control. Its boundary is derived from the immutable receipt instant already assigned to the input batch, so grouping survives archive reopen without a metadata migration; unrelated text in the same transfer remains its own card.

The exact Release source passed **20/20 suites and 1,825 checks**, including new preference validation, native Finder batches, promised-file batches and archive-reopen grouping. Local PDF, RTF and H.264 processing passed **39/39**. **28 production-view renders** passed with the production Dark mode preference as the only appearance driver; grouped cards and Settings were inspected in light and dark, including native 2× samples.

The optimized ARM64 build, strict signature, generated Xcode inventory and **18/18 static App Store packaging checks** passed. Version **0.2.2 (24)** is installed and running from `~/Applications/DaBin.app`; the installer left the capture archive untouched and preserved the previous app. The dedicated update ZIP passed isolated fresh-install, replacement, backup, signature, hash and live confirmation-dialog checks. The live rehearsal was cancelled before installation.

[Release evidence](build/qa/release-v0.2.2.json) · [Full optimized run](build/qa/runs/20260923T121820562041Z/report.json) · [Production renders](build/qa/screenshots/release-ui-renders.json) · [Media integration](build/qa/media-integration-v0.2.2.log) · [Static App Store preflight](build/qa/app-store-preflight-static-v0.2.2.log).

## Translucent board and visible capture actions — 0.2.1 (23)

The floating board now draws its base surface at exactly **75% opacity** over the clear native panel. Text, icons, previews and controls remain fully opaque. Every capture card in Daily, Week, Search and Reminders retains a visible minimize/expand button and a separate trash button; both now use larger purple icon surfaces. Delete still requires confirmation and preserves the source file. Minimize remains persistent and keeps the capture searchable, editable and available in Detail.

The complete optimized suite passed **20/20 suites and 1,812 checks**. The additional check locks the board opacity at 0.75. Removal/minimize persistence, rollback, reminder cleanup, 203 two-display window checks, 138 Daily input checks, weekly cards and filter resizing all pass. The separate PDF/RTF/H.264 and optional public-link run passed **41/41**, for **1,853 current automated checks** in total.

**26 production-view renders** passed in light and dark appearances, including four native 2× Retina samples. Direct PNG inspection measured **0.7490 alpha** at unobstructed board-background points in both appearances, the 8-bit representation of 0.75. The new capture controls fit expanded and minimized cards without clipping.

[Full optimized run](build/qa/runs/20260923T100551361291Z/report.json) · [Current renders](build/qa/screenshots/release-ui-renders.json) · [Render log](build/qa/release-ui-v0.2.1.log) · [Media integration](build/qa/media-integration-link-v0.2.1.log) · [Opacity/action evidence](build/qa/translucency-v0.2.1.json) · [Release build](build/qa/build-v0.2.1.log).

A dedicated local update ZIP now contains the verified DaBin app, a native **DaBin Update.app**, the PDF guide, instructions and a hash manifest. The exact updater binary passed an isolated fresh install and a second replacement run. The second run created and verified one previous-app backup; both installed copies matched the Release executable hash and strict signature. Its live confirmation showed the current and update versions and the archive-preservation explanation; Cancel exited without installing. The rehearsal used a temporary destination, did not quit the installed app and did not open the production archive. [Update-package evidence](build/qa/update-package-v0.2.1.json).

## Native standalone refactor — 0.2.0 (22), 23 September 2026

**Installed local Release candidate; all registered local automated suites pass. App Store distribution still needs owner and Apple release inputs.** The optimized ARM64 build passed compilation with warnings treated as errors, strict local signing and verified standalone packaging. After the Mac was unlocked, one clean full run passed **20 of 20 suites**. Input hashes remained stable throughout the run.

### Architecture and reliability changes

- Swift/AppKit/SwiftUI application with its own resources and only Apple system-framework dependencies. No browser runtime, server, helper install or downloaded code is required.
- A composition root owns storage, services, shared preferences, native panels and commands. The small macOS delegate handles launch, reopen and safe quit. Native About, Hide, Show All, app commands and responder-chain editing are explicit.
- The 1,129-line board view is now a 132-line shell with cohesive feature files and shared components. The UI split preserved all 27 existing declaration bodies apart from visibility needed between files.
- Startup/shutdown is explicit and idempotent. Timers, notifications, keyboard monitors, preview work, hosting views and callbacks are released. A regression exposed a retained SwiftUI view at shutdown; detaching hosting views fixes it. Stale corner callbacks cannot reopen a stopped session.
- Preview cancellation now reaches native QuickLook/video requests promptly. Concurrent preview-cache directory creation tolerates a verified directory created by another worker while rejecting symlinks or files.
- One source inventory drives local build, Xcode and tests. Release compilation uses ARM64, optimization, whole-module compilation and warnings as errors. Symbols are outside the app. Build/test/package receipts preserve hashes and failures.

[Architecture](ARCHITECTURE.md) · [Release build log](build/qa/build-v0.2.0.log) · [Build receipt](build/build-receipt.json).

### Full optimized QA results

| Suite | Passed checks / outcome |
| --- | ---: |
| Theme settings and contrast | 153 |
| Privacy information | 24 |
| Domain/persistence/search | 185 |
| Archive layout and path safety | 50 |
| Archive store and recovery | 81 |
| Removal/minimize/source preservation | 76 |
| Preview/reminder services | 61 |
| Scoped storage and 1,000-record fixture | 22 |
| Lifecycle/cache recovery | 22 |
| Application ownership/menu/shutdown | 29 |
| Native preview cancellation/shutdown/concurrent cache | 130 |
| Tasks and carryover | 109 |
| Capture actions and deletion races | 30 |
| Weekly state | 99 |
| Paste/drop representations and promised-file intake | 103 |
| **15 non-focus suites subtotal** | **1,174** |
| Weekly native windows | 76 |
| Filter/minimize/expand panel transitions | 110 |
| Native robot drag destination callbacks | 110 |
| General native windows across two displays | 203 |
| Daily paste/drop, shortcuts and controller integration | 138 |
| **20-suite optimized total** | **1,811** |
| Separate real-media/public-link integration | 41 |
| **Complete automated total including media** | **1,852** |

The first run while macOS was locked retained two general-window keyboard-focus failures and one Daily key-window failure. After unlocking, the complete suite was rerun from the start without weakening or excluding those assertions: all **203/203** general-window checks and all **138/138** Daily checks passed. The final report below is the unlocked run.

The runner used Swift 6.3.2, SDK 26.5, macOS 26.6.2, ARM64, `-O` and whole-module optimization. Input hashes did not change during the run. Final production source/resource hashes were compared with the built application receipt and match. Temporary archives, private pasteboards and fake notifications protected real captures. Expected corrupt-store diagnostics belong to an intentionally invalid fixture.

[Full run and every per-suite log](build/qa/runs/20260923T094648766418Z/report.json) · [Media integration](build/qa/media-integration-link-v0.2.0.log) · [Live release verification](build/qa/live-release-v0.2.0.json) · [Final source/build/package evidence](build/qa/final-source-v0.2.0.json).

### Visual and media QA

**26 production-view layouts were individually reviewed:** 22 at 1× and 4 rendered directly at 2× on an actual Retina backing surface. Coverage includes light/dark compact Daily, empty Daily, minimized task, full/narrow Week, contextual Search, fitted Detail preview, scrolled Detail editor, Settings top/bottom and New Task. Header geometry, action controls, fitted previews, scroll areas, typography and icon rendering passed the reviewed fixtures. Retina samples were inspected at original resolution. No screenshot was enlarged to simulate Retina.

[Render manifest and review limits](build/qa/screenshots/release-ui-renders.json) · [Render execution log](build/qa/refactor-release-ui.log).

The separate optimized media run passed all 41 checks: synthetic PDF/RTF/H.264 MOV previews, original-byte preservation, nonblank fitted thumbnails, distinct decoded video frames, reopened metadata and portrait/landscape PDF pages fitting ordinary/narrow viewports. Two checks exercised Apple's public homepage with isolated opt-in preferences. No personal file, URL or capture was sent. This sample coverage does not certify every third-party format or codec.

Live verification of the installed app passed weekly navigation, empty-day/task filtering, contextual search, settings, the complete in-app privacy explanation, hide/keyboard reopen and a fitted document preview with its source location. No production capture was changed. A separately signed 0.2.0 QA app with an isolated sandbox passed direct Daily paste, newest-first ordering, minimize/expand, task creation, Task → Completed → Task, comment save and search-by-comment with neighboring context. Its two fictional records and sandbox were removed after verification.

CUA's synthetic drag still ends its native dragging session before AppKit reports a destination callback; the isolated diagnostic records that limitation. Production native destination callbacks, copy-only transfer rules, file/text representations, exact source bytes and controller integration pass the automated suites. A physical Finder/browser drag remains a manual acceptance check. Real notification permission/delivery/reopen was not changed because enabling notifications is a user-controlled system permission; VoiceOver interaction, Spaces/Hot Corners behavior and macOS 14/15 runtime acceptance also remain external coverage. “Pixel perfect” across every display, accessibility setting and supported OS cannot be established from one machine.

### Installed application and standalone ZIP

DaBin **0.2.0 (22)** was installed at `~/Applications/DaBin.app` after the previous app quit normally. Its prior version is preserved at `~/Applications/.DaBinBackups/20260923-102137-96f927b9.app`. Strict signature and executable-hash verification passed. The installed app was exercised live in the unlocked session and left on today's Daily view with All selected. The Desktop shortcut still points to this installation. No personal capture was added, edited, minimized or removed by QA.

[Installed verification](build/qa/installed-app-v0.2.0.json).

`../output/downloads/DaBin-0.2.0-AppleSilicon.zip` contains the standalone application, friendly launch instructions, the existing one-page PDF guide and a file manifest. Packaging verified Release/ARM64/system-library dependencies, every ZIP hash, extracted executable permissions and strict extracted-app signing. It excludes developer caches and personal captures. The package remains locally ad-hoc signed and has not been notarized or approved by the Mac App Store.

### Store gate

**18 static source checks pass; four release inputs remain blocked:** full Xcode, Apple Developer Team ID, real privacy-policy URL and real support URL. Publisher identity, Bundle ID ownership, distribution signing/validation, App Store Connect metadata and Apple review are also necessary. No account, certificate or public submission was changed. See [App Store readiness](APP_STORE_READINESS.md).

## Previous 0.1.20 cycle (historical evidence)

## Current update: 0.1.20 (21)

**Installed. Local automated QA passed in the areas listed below; live focus/notification acceptance and Mac App Store submission remain incomplete.** This is not an unconditional release sign-off.

### Changes delivered

- Every capture has a small **minimize/expand chevron** and **trash icon** in Daily, Week, contextual Search and Reminders. Minimized state persists, keeps title/time/type or task toggle and Comment/Reminder controls, and does not remove content from search or full Detail.
- Removal requires one confirmation, deletes only that capture's DaBin-owned records/copies, clears its reminder, and preserves source files and other captures. Durable removal intent retries interrupted cleanup before import recovery; stale service writes cannot restore a deleted record. Background preview work is drained first. Quitting is blocked while removal and reminder cleanup are still in progress.
- Daily's bottom edge animates during minimize/expand with its header fixed. Height accounts for long titles, comments and task creation labels so controls remain in the initial viewport where screen space permits. Taller collections remain scrollable.
- Detail now explains failed previews and expired reminders. Expired reminders guide users to choose a future time. Lost link thumbnails can rebuild only when website previews are enabled; metadata-only cards do not refetch unnecessarily.
- Settings includes an offline privacy policy and clearer optional website-preview disclosure. Both builds bundle the policy and privacy manifest; release metadata includes the Productivity category. Release signing configuration, a preflight and archive helper are supplied.

### Automated checks on this update

| Suite | Passed checks |
| --- | ---: |
| Theme persistence and contrast | 153 |
| Privacy information and manifest | 24 |
| Domain, persistence, classification and search | 185 |
| Dated archive layout/path safety | 50 |
| Archive integration and recovery | 81 |
| Removal, minimize, interruption and source preservation | 76 |
| Preview/reminder services and deletion races | 61 |
| Scoped storage and 1,000-record benchmark | 22 |
| Lifecycle/cache recovery | 22 |
| Task workflow and carryover | 109 |
| Capture actions, confirmation state, drafts and reminder deletion races | 30 |
| Weekly state | 99 |
| Input representations/promises/partial failures | 103 |
| **Storage/service/state subtotal** | **1,015** |
| Weekly native window states | 76 |
| Native filter/minimize/expand panel transitions | 110 |
| Native robot drag destination callbacks | 110 |
| Real PDF/QuickLook/video integration and optional public-link smoke | 41 |
| **Complete passing suites total** | **1,352** |

The main storage log contains the first 67-check removal suite and 28-check action suite. The final targeted reruns extend those to 76 and 30, respectively; the totals above use the final count once per suite. The other final-source suites retained their passing results. The media network run includes the same 39 local checks plus 2 website checks; these are counted once. Fixtures used temporary archives, private pasteboards and fake notifications. No real capture was removed or minimized by QA. The expected corrupt-database messages verify preservation of a deliberately invalid test store.

Evidence: [storage regression](build/qa/full-qa-storage-v0.1.20-final.log), [final removal](build/qa/capture-removal-v0.1.20.log), [final capture actions](build/qa/capture-actions-v0.1.20.log), [final resize](build/qa/FilterResizeTests-v0.1.20-final.log), [weekly](build/qa/WeeklyWindowTests-v0.1.20-final.log), [robot](build/qa/RobotDropTests-v0.1.20-final.log), [media and public link](build/qa/media-integration-link-v0.1.20.log).

A 1,000-record fixture saved one scoped state update in about 0.0030 seconds and one text preview update in about 0.0025 seconds. Performance values are local measurements, not a cross-device guarantee.

### Visual and real-media verification

**22 native capture-action layouts** and **6 recovery-guidance layouts** were visually inspected in light/dark appearances. The action set uses production Daily sizing and includes expanded/minimized long notes, images, open/completed tasks, full Week and narrow Week. Comment, Reminder, minimize and remove controls fit; title/time/task status remain readable. Initial clipping candidates are clearly retained under `build/qa/diagnostics/`, outside the approved render manifests. These are production-view renders, not live pointer interaction.

[Capture-action render manifest](build/qa/screenshots/capture-actions-renders.json) · [Recovery-guidance manifest](build/qa/recovery-guidance/recovery-guidance-renders.json).

A separate privacy-sheet probe passed **11 checks**, with **four light/dark top/bottom renders** of the full bundled policy. All six sections, Done, and the data-folder control are readable and reachable; missing public URLs do not create invented links. No foreground application change occurred. [Privacy render manifest](build/qa/privacy/privacy-renders.json) · [Privacy probe log](build/qa/privacy/privacy-render.log).

Real media integration generated synthetic PDF, RTF and H.264 MOV files and exercised the production preview service: nonblank thumbnails, unchanged original hashes, distinct decoded video frames, persisted state, and native fitted-PDF geometry for both pages at two viewport sizes passed. A separate opt-in test fetched Apple's public homepage using isolated preferences; no personal content or saved URL was sent. Unsupported or malformed formats are retained with an original-file fallback; testing these sample formats is not a claim that every third-party format/codec renders.

The implemented categorization is by content type. Automatic AI project assignment from the original concept is not implemented. Folder and symbolic-link imports are rejected with feedback; this build accepts individual supported transfer representations, not every possible draggable object.

### Locked-session limits and outstanding acceptance

macOS was confirmed locked. The general window suite attempted all 203 assertions: 201 passed and **2 keyboard-focus assertions failed**. The Daily suite stopped at its native Edit-routing focus check. These failures are retained in the report and were not disabled or counted in the complete passing-suite total. The locked session prevents a final determination of those focus behaviors on this build; the earlier unlocked 0.1.18 run passed, but that is historical evidence only.

[Window attempt](build/qa/WindowTests-v0.1.20.log) · [Daily focus attempt](build/qa/DailyCaptureTests-v0.1.20.log).

Still needed: unlock and rerun those two suites; live collapse/expand and Remove/Cancel interaction on fictional captures; physical Finder/browser drag-and-drop and hover Control-V; notification permission, actual timed delivery while running/quit and notification-click reopening; VoiceOver/system accessibility interaction; oldest-supported macOS and hardware/Spaces/Hot Corners coverage. Unit scheduling and native drag callbacks do not replace those checks.

### Build, installation and App Store result

The final native ARM64 build and strict installed-app signature passed. DaBin quit normally through its own application handler before replacement; no process was forcibly terminated. Version **0.1.20 (21)** was installed at `~/Applications/DaBin.app`, with the previous app saved at `~/Applications/.DaBinBackups/20260923-095330-1ff6d689.app`. The app was launched and its running process observed. The installed executable and bundled privacy resources match the final build. Live visual launch verification remains blocked by the locked session. The existing Desktop link continues pointing to this installation.

[Build log](build/qa/build-v0.1.20.log) · [Installed verification](build/qa/installed-app-v0.1.20.json) · [Final source/resource hashes](build/qa/final-source-v0.1.20.json).

**App Store submission is blocked.** Thirteen source packaging checks pass; the release gate identifies four missing inputs: full Xcode, the Apple Developer team, published privacy-policy URL and real support URL. App Store signing, Bundle ID ownership, distribution validation, listing metadata/contacts and Apple review remain necessary. The current app is an ad-hoc local development build. No credentials were accessed and no app/policy was published or submitted. [Apple requirements audit and release workflow](APP_STORE_READINESS.md).

## Earlier recorded QA cycles

Previously installed version: **0.1.19 (20)** repairs the weekly entry control: **Today opens This Week**, with today and the preceding six dates. The weekly control reads **This Week** and all seven columns remain visible with no captures or tasks. The directional slide remains; columns no longer depend on an opacity animation to become visible. **175 targeted checks passed:** 99 weekly state checks and 76 native weekly window checks. **8 native renders** cover empty Daily/Week, empty Tasks and a narrow weekly viewport in both appearances. Native build, strict installed-app signing and plist/project validation passed. [State checks](build/qa/weekly-state-tests-v0.1.19.log) · [Window checks](build/qa/weekly-window-tests-v0.1.19.log) · [Renders](build/qa/weekly-entry-renders-v0.1.19.log) · [Render manifest](build/qa/screenshots/weekly-entry-renders.json) · [Build](build/qa/build-v0.1.19.log).

**Live navigation passed in the installed app:** select an empty Links filter in Daily → click Today → the window changes to Week, the control reads This Week, and all seven date headings show zero captures with seven No links messages. Clicking an empty day opens that date in Daily; clicking Today opens the current week again. All was restored and the app was left on This Week, showing the existing archive. No captures, tasks, comments or reminders were added or edited. The previous app is preserved at `~/Applications/.DaBinBackups/20260923-084418-b70795c3.app`. [Live verification](build/qa/live-weekly-entry-v0.1.19.json).

The optional own-process SwiftUI accessibility probe exposed only host nodes; that unsupported test approach is retained as a diagnostic, outside the passing suite. The actual buttons and seven empty headings were verified through CUA in the running installed app instead. Native tests cover empty-store expansion, every empty filter, selecting an empty day, calendar boundaries, drafts retained and unchanged persisted storage.

The preceding **0.1.18 (19)** adds direct paste and drag-and-drop to Daily, using the existing capture/import pipeline. **647 targeted checks passed:** 138 new Daily capture checks, 103 input lifecycle checks, 203 native window checks, 93 filter-resize checks and 110 robot-drop regression checks. Native build, strict installed-app signature and plist/project validation passed. [Daily capture checks](build/qa/daily-capture-v0.1.18.log) · [Input lifecycle](build/qa/InputTests-v0.1.18.log) · [Window regression](build/qa/WindowTests-v0.1.18.log) · [Filter regression](build/qa/FilterResizeTests-v0.1.18.log) · [Robot regression](build/qa/RobotDropTests-v0.1.18.log) · [Build](build/qa/build-v0.1.18.log).

Tests cover text/link/image/file drops, durable local originals, source bytes and timestamps, unsupported/move-only/cancelled drops, normal child hit testing, temporary highlight lifecycle, Control-V/Command-V, Edit → Paste responder-chain resolution, repeat/duplicate protection, normal native text editing, failure handling, and navigation while a capture is saving. They exposed a pre-existing RobotView shortcut bug: reading the mouse-only `NSEvent.eventNumber` on a key event can throw an AppKit exception. Both robot and Daily handlers now deduplicate using key-safe metadata, with a regression test for distinct objects representing the same key event.

**Live paste verification passed** in a separately signed QA app with its own sandbox: pasting a fictional note directly into Daily created one visible capture and displayed saved feedback. An additional document appeared through user interaction during that check; its saved test-app capture was preserved, with transfer preference requested. It was not inspected or included in this delivery. A physical Finder-to-Daily drag was not completed by the automation in this cycle; native destination callbacks and hit routing are tested above. The normal app was quit cleanly, installed, reopened on Daily, and showed the same four existing captures for today. The previous app is preserved at `~/Applications/.DaBinBackups/20260923-083351-7f1b6a77.app`. [Live verification](build/qa/live-daily-capture-v0.1.18.json).

The included **0.1.17 (18)** filter update keeps Daily/Search headers fixed and eases the bottom edge over 0.38 seconds. Growth stops at the display bottom and leaves overflow to existing scroll views. Its original 93 filter/window and 61 weekly checks passed. The former locked-session focus and installation block is now resolved: all 203 general window checks and 93 filter checks passed on the final 0.1.18 source, and the combined update is installed. [Original weekly checks](build/qa/weekly-window-tests-v0.1.17.log).

The preceding **0.1.16 (17)** adds **Settings → Theme color**, with six presets, a native custom color well and Reset. **153 preference/contrast checks** passed for persistence, invalid stored values, color-space conversion and light/dark accents. **19 native renders** passed, covering all presets, custom Settings/Daily/detail, both appearances and narrow Settings. The selected accent reaches filters, dates, actions, the logo and carryover frames; task status colors retain their red/green meanings. [Theme checks](build/qa/theme-settings-v0.1.16.log) · [Theme renders](build/qa/theme-renders-v0.1.16.log) · [Render manifest](build/qa/screenshots/theme-renders.json) · [Build](build/qa/build-v0.1.16.log).

Live verification in the installed app passed: Purple → Teal updated immediately; quit/relaunch retained Teal in both Daily and Settings; Reset restored Purple and the correct selected-state accessibility labels. The native Custom theme color well is present; custom conversion and persistence were exercised by isolated model checks, while separate macOS color-panel editing was not automated. Native build, strict installed-app signature and plist/project validation passed. No captures were added or edited. Previous app preserved at `~/Applications/.DaBinBackups/20260923-073248-6490b52e.app`. [Live theme verification](build/qa/live-theme-v0.1.16.json).

The preceding **0.1.15 (16)** fits previews to their compact viewport while preserving proportions. **16 image/document renders** pass four-corner raster checks across tall/wide images, Daily thumbnails, 260/380-point widths and both themes. **8 additional PDF renders** verify surrounding layout only: macOS view caching omits PDFKit's tiled page drawing. **18 native PDF checks** verify complete-page fit, portrait/landscape pages, narrower bounds, page retention, navigation and URL changes. Native build, clean-copy signing, strict installed-app signature and project/plist validation passed. [Preview render log](build/qa/preview-fit-v0.1.15.log) · [Render manifest](build/qa/screenshots/preview-fit-renders.json) · [PDF checks](build/qa/pdf-fit-probe-v0.1.15.log) · [Build](build/qa/build-v0.1.15.log).

Live CUA verification of the production PDF component in an isolated fixture app passed: the complete portrait page and complete landscape page both display all four coloured corner markers; Next changes 1/2 to 2/2, and Previous returns to 1/2 with the correct disabled end buttons. This resolves the blank cached-PDF snapshot question without substituting generated page pixels for a real native preview. No personal captures were involved. The briefly locked screen was unlocked by the user, and the app was then quit cleanly and updated. Previous build preserved at `~/Applications/.DaBinBackups/20260923-072422-b5fe4d9d.app`. [Live verification record](build/qa/live-preview-fit-v0.1.15.json).

The preceding **0.1.14 (15)** repairs direct file/text drop behavior on the robot, including while Daily or Week is open. **416 targeted checks passed:** 103 input lifecycle checks, 110 robot/drop integration checks and 203 existing native window checks across two displays. Native build, strict installed-app signature and project/plist validation passed. The app was quit cleanly, installed, and reopened on today's Daily view. Previous app preserved at `~/Applications/.DaBinBackups/20260923-065654-989395b5.app`.

New tests cover native multi-file URL representations and transfer metadata, selected plain/RTF/browser text, no payload reads during hover, source bytes and timestamps preserved, copy-only acceptance, rejected/cancelled drops, the robot artwork/badge hit target, all corners while Daily is open, digestion visibility, and retirement. A first-open Daily board keeps its top-left and display after receiving a drop at a different corner and resizing; no unintended placement preference is saved. Tests use temporary archives and private named pasteboards. [Input log](build/qa/input-drag-v0.1.14.log) · [Robot/drop log](build/qa/robot-drop-v0.1.14.log) · [Window log](build/qa/window-tests-v0.1.14.log) · [Build](build/qa/build-v0.1.14.log).

**Live drag limitation:** the isolated native fixture launched, but CUA's drag gesture delivered mouse events without AppKit destination callbacks, so no fixture transfer completed. This is not a live Finder/browser-to-sandbox pass. The production callback/import path is covered by the tests above; a physical cross-application drag remains a manual check. The diagnostic is retained in [native drag attempt](build/qa/native-drag-attempt-v0.1.14.json). `scripts/build_drop_qa.sh` builds a fixture-only app for repeating native drag checks; its archive is separate from normal DaBin. No personal capture content was added or edited by this update. Broad storage tests and board renders were not repeated for this input change.

The preceding **0.1.13 (14)** adds the seven-day weekly board opened from Daily's date. **447 targeted checks passed:** 109 existing task checks, 74 weekly state checks, 61 weekly window checks and all 203 existing window checks across two displays. **60 native view renders** passed, including populated/empty/task-filter weeks, both themes and an 800-point narrow layout. Native build, clean-copy signing and project/plist validation passed. [Task regression](build/qa/task-regression-v0.1.13.log) · [Weekly state](build/qa/weekly-state-v0.1.13.log) · [Weekly windows](build/qa/weekly-window-tests-v0.1.13-unlocked.log) · [Existing windows](build/qa/window-tests-v0.1.13-unlocked.log) · [Build](build/qa/build-v0.1.13.log) · [Renders](build/qa/render-v0.1.13.log).

Native window tests verify both unfolding directions, actual intermediate resize frames, screen clamping, rapid reversal, compact-position restoration, detail return, weekly dragging and the Reduce Motion policy. Calendar tests include year/leap-month/DST boundaries, midnight/wake, filters and unchanged archive bytes. The initial locked-screen run failed two keyboard-focus assertions; both passed after unlocking without weakening the assertions. The last accessibility-only refinement was then confirmed in the installed app: unselected Tasks no longer announces Selected, and decorative checkmarks are hidden from the accessibility tree.

Live CUA verification passed: date → seven side-by-side days; Tasks filter → one existing task; day heading → compact Daily on that day; Today → current day; weekly capture → detail → original week. The app was quit cleanly, updated, reopened, and left on the current week with All selected. The same three existing captures remain; no live records were added or edited. All accumulated updates since 0.1.8 are installed. The original 0.1.8 app is backed up at `~/Applications/.DaBinBackups/20260922-232649-e38ec038.app`; the final installation also retained its preceding candidate. [Live verification record](build/qa/live-weekly-v0.1.13.json).

The included **0.1.12 (13)** change moves capture types below the time, puts the task status toggle there without a duplicate label, increases row titles exactly 15%, and adds the purple checkmark Tasks filter. **185 domain assertions + 109 task workflow checks (294 total)** and **52 native view renders** passed, together with native build/signing and project/plist validation. Tasks includes open/completed tasks while respecting creation, carryover and reminder dates; Search restricts hits to tasks while preserving neighbor context. Native renders cover the new task/file filters, task search, notes, media and scheduled-task frames in both themes. The status toggle is a sibling of the open-capture button. [Domain tests](build/qa/domain-v0.1.12.log) · [Task tests](build/qa/task-filter-v0.1.12.log) · [Build log](build/qa/build-v0.1.12.log) · [Render log](build/qa/render-v0.1.12.log).

The included **0.1.11 (12)** change shows unfinished tasks with reminders at the top only on their reminder date; tasks without reminders retain daily carryover. Same-day reminders receive the same purple frame, once. Original-day records are preserved. **100 task workflow checks** (38 new reminder-day checks), **46 native view renders**, native build/signing and project/plist validation passed. Tests cover before/on/after dates, midnight transitions, completion/reopening, edits/removal, filtering, current-local reminder dates, no duplicates and unchanged original archive locations. Before/day/after layouts were inspected in light/dark mode. [Task tests](build/qa/task-reminder-day-tests-v0.1.11.log) · [Build log](build/qa/build-v0.1.11.log) · [Render log](build/qa/render-v0.1.11.log).

The included **0.1.10 (11)** change replaces the Daily heading with a custom native DaBin wordmark and metallic purple robot-bin emblem. The existing 30-point header and drag overlay are retained. Native build/signing, project/plist validation and **40 native view renders** passed. The light/dark logo, carried-task rows, toolbar spacing and compact empty layout were visually checked. No behavior or storage logic changed in this logo update. [Build log](build/qa/build-v0.1.10.log) · [Render log](build/qa/render-v0.1.10.log).

The included **0.1.9 (10)** change adds unfinished-task carryover at the top of Daily, original creation dates and thin purple frames. **62 task workflow checks** (32 new carryover checks) and **40 native view renders** passed. Coverage includes skipped days, year/month boundaries, filters, completion/reopening, unchanged original archive locations, no duplicate records, time-zone receipt dates, midnight refresh and the actual calendar-day notification. Light/dark carryover renders were inspected. Native build/signing and plist/project validation passed. [Task tests](build/qa/task-carryover-tests-v0.1.9.log) · [Build log](build/qa/build-v0.1.9.log) · [Render log](build/qa/render-v0.1.9.log).

The earlier 0.1.9–0.1.12 installations were held while the screen was locked; that installation block is now resolved by 0.1.13 above. The full storage/service suite was not rerun for these scoped interface updates; the affected task, weekly and window suites were exercised.

The **0.1.8 (9)** release made the title/blank header move the board, with a locally remembered position across route changes, hiding and relaunch. Native build/signing, **203 window checks across two displays**, and **38 view renders** passed. New checks dispatch mouse events directly to the actual native header, verify no snap-back while dragging or resizing, restore saved placement, and recover from invalid/disconnected-display coordinates. A live CUA drag on the installed app successfully saved a new window position. [Window log](build/qa/window-tests-v0.1.8.log) · [Build log](build/qa/build-v0.1.8.log) · [Render log](build/qa/render-v0.1.8.log) · [Live movement evidence](build/qa/movable-daily-v0.1.8.json).

The preceding **0.1.7 (8)** update enlarged capture-row timestamps by 15% (11 → 12.65 pt), verified by native builds and renders. The full QA cycle below covers **0.1.6 (7)**; the storage/service logic was not changed or broadly retested for these UI follow-ups.

**657 automated checks passed. 38 native view renders passed. Live native capture, search, comment, task and relaunch workflows passed.** Notification delivery and some cross-application input checks remain open; this is not an unconditional release sign-off.

## Fixes made during this cycle

| Finding | Repair and verification |
| --- | --- |
| One preview/reminder update rewrote the whole archive and blocked the UI | Services save only changed records. In a synthetic 1,000-record archive, one state update improved from approximately 2.14 seconds to **0.0027 seconds** in the final run. Scoped-save tests verify unrelated metadata and sidecars remain untouched. |
| Failed notification-state writes could suppress later retries | Restore the previous in-memory state after persistence failure; a later reconciliation is proven to save it successfully. |
| Notification permission changes required manual retry/relaunch | Reconcile on activation and wake, without requesting permission. Event bursts coalesce; tests cover permission changes and concurrent events. |
| Deleted thumbnail caches were not rebuilt at launch | Pass all captures to the preview service; missing local thumbnails regenerate and intact thumbnails are skipped. |
| Capture failures displayed a success icon | Explicit success/warning/error message types and matching icons; partial batches have warning feedback. |
| New task reminder failures were hidden after returning to Daily | Scheduling/permission failures are visible on the board; retries update the message. |
| Partial capture failures sounded successful to assistive technology | The robot announcement now identifies both saved and failed items. |
| Reminder failures remained after clearing/completing the task | Feedback belongs to its capture and current reminder revision; clearing removes the matching notice without erasing unrelated errors or restoring stale async messages. |

## Automated results

| Suite | Passed checks |
| --- | ---: |
| Domain, persistence, classification and contextual search | 171 |
| Dated archive layout and path safety | 50 |
| Archive integration, migration and interruption recovery | 81 |
| Preview/reminder services | 36 |
| Scoped persistence, failures and 1,000-record archive | 22 |
| App lifecycle and missing-cache recovery | 22 |
| Task workflow and feedback races | 30 |
| Pasteboard and promised-file lifecycle | 57 |
| Native window states across two attached displays | 188 |
| **Total** | **657** |

[Final full-suite log](build/qa/full-qa-tests-v0.1.6-final.log).
All suites ran against the final source. Fixtures use temporary stores, private named pasteboards and fake notification clients. The automated suite never reads the general clipboard or personal captures. Expected Core Data diagnostics come from an intentionally corrupt fixture; the fixture verifies preservation of its bytes.

The first window attempt failed while macOS was locked. After unlocking, the full window suite passed twice. Assertions were not disabled: the runner now reports every independent failure and still exits unsuccessfully if any fail. It checks actual NSPanel/NSHostingView instances, internally supplied pointer positions, all four corners, retreat, focus acquisition/release, drag exclusion, keyboard routing and two-screen geometry. It does not synthesize a physical cross-app drag.

## Native rendering and live interaction

**38 production-view renders** cover light/dark Daily, compact empty board, media, contextual search, source paths, comments/reminders, active/completed tasks, task forms, Settings, capture errors and notification warnings. Inspected layouts show no clipping of essential controls. The robot changed **15,499 raster bytes** between active frames and **0 bytes** while inactive.

[Render log](build/qa/full-qa-render-v0.1.6-final.log) · [Render manifest](build/qa/screenshots/native-view-renders.json).
These are native view snapshots, not desktop screenshots. Live desktop screenshots and accessibility trees were inspected separately through the native UI tool.

Live testing used the isolated bundle `com.dabin.mac.qa.cycle58ff3dc821`, with four fictional captures in its own sandbox:

- Text and URL pasted directly to the robot, then visible in Daily newest first.
- Search for the fictional URL returned its date, the matching link and the immediate note before and after. Selecting Links retained the neighboring text context.
- A comment saved in Detail appeared on Daily and survived quit/relaunch.
- The plus button created a task at the top of Daily. Task → Completed → Task worked and the reopened task survived relaunch.
- Ordinary copied text honestly showed unavailable source metadata. The link showed its exact URL.
- Show saved folder opened the matching year/month/day/capture folder in Finder, with readable generated records.
- Saving a reminder retained its desired date when native authorization failed and displayed a clear error. Clearing the reminder was exercised; the stale-error finding was then repaired and covered by final regression tests.

The live run used the 0.1.6 QA candidate. The final feedback-cleanup adjustment was subsequently covered by the full suite, new renders and the rebuilt installed application. QA data was retained separately; it was not seeded into normal DaBin storage.

## Notification integration: permission response still needed

The temporary QA application under `/private/tmp` was rejected by macOS notification client validation. An identical signed copy under `~/Applications` passed validation and macOS presented its permission alert. The desired reminder remained pending while authorization awaited a response. At the end of testing, the synthetic task was marked Completed (the board showed Paused) and the QA app was quit, so it will not produce a later test alert. This controlled comparison resolved the temporary-location rejection without changing signing or entitlements.

Permission approval was requested from the user. **Real notification delivery, delivery while quit and notification-click reopening are not marked passed.** See [scoped diagnosis and Apple API references](build/qa/notification-validation-v0.1.6.md). Fake-client scheduling tests do not substitute for this OS integration check.

## Build, installation and delivery

- Native ARM64 build and strict signature verification passed. Installed app reports **0.1.6 (7)**. [Final build log](build/qa/full-qa-build-v0.1.6-final.log).
- The previous installed app was preserved at `~/Applications/.DaBinBackups/20260922-222611-7c6a798e.app`. The normal app was quit cleanly before replacement. The final installed build was launched through macOS and showed the same three existing captures; no QA fixtures appeared in that archive.
- Xcode project, Info.plist and entitlements passed `plutil -lint`. The new lifecycle source is included in the generated Xcode project.
- The robot SVG remains byte-identical to the supplied handoff.
- The earlier delivered ZIP passed CRC, all 209 manifest hashes, executable permissions and strict signature verification after clean extraction. The final updated delivery is validated again by the guarded packaging script.
- Synced Desktop/Documents app folders can receive FinderInfo attributes from the provider. Clean signed contents and the installed Applications copy are verified; use the installed app.

## Remaining acceptance checks

- Physical-pointer hover with real Control-V from another app, Finder/browser drag-and-drop, live external file promises, and active-drag corner reveal. Finder file-copy/paste automation in this cycle was inconclusive and is not counted as passing.
- Notification permission response, actual timed delivery, delivery while quit, Focus behavior and notification-click reopening.
- Separate Spaces/fullscreen apps, configured macOS Hot Corners, physical display removal and pointer traversal between displays.
- Live website preview fetching, redirects and offline behavior; network previews remained off during this cycle.
- VoiceOver navigation and system Increase Contrast/Reduce Motion. Labels, partial-success announcements and the static Reduce Motion branch were reviewed, but full assistive-technology interaction was not run.
- Intel and macOS 14–25 runtime coverage; Developer ID signing/notarization for distribution; full Xcode build/XCTest execution.

## Environment

Apple Silicon; macOS **26.6.2 (25G83)**; Apple Swift **6.3.2**; Command Line Tools macOS SDK **26.5**; Swift 5 language mode; macOS 14 minimum target. Full Xcode is not installed. Data and QA artifacts stayed local; only synthetic DaBin fixtures were used.
