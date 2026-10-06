# DaBin Quick Guide source

The latest source candidate is 0.4.43 (98); its paused companion and security changes are documented in [current release notes](../../docs/RELEASE_NOTES_0.4.43.md). The PDF and render assets here remain the visually reviewed 0.4.41 (96) draft. They have not been regenerated or compared with a distribution-signed 98 app. [Current validation and signing status](../../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/status.json).


The current [DaBin Quick Guide](../../docs/DaBin-Quick-Guide.pdf) and [Friendly Copy](../../docs/DaBin-Friendly-Copy.txt) describe **0.4.41 (96)**. Both landscape A4 pages were rendered and opened at original resolution after the coordinated Store QA and asset-export stage. The guide explains one-click opening, compact Captions/Tasks/Projects controls, the day/week date picker, Export Selected, colored priorities and the companion’s still response in Quiet mode or Reduce Motion. Page one uses the current native project workspace with measured callouts. Page two shows the date-column Search view and everyday saving habits.

The [local review workflow](../app-store-pack/README.md) records export, authoring, rendering and packaging commands. Exact current source/module paths and output hashes are in [review-pack-authoring-plan.json](../../docs/qa/full-review-2026-10-05/review-pack-authoring-plan.json). The [guide visual receipt](qa/robot-guide-0.4.41-96.json) and [final all-page review](../../docs/qa/full-review-2026-10-05/review-pack-final-visual.json) record actual inspection findings. The guide remains a local review draft: strict zoom performance failed, and distribution signing, signed-app acceptance, owner declarations and Apple review remain pending.

## Source and native assets

`copy.json` is the shared guide prose. `build_guide.py` writes identical PDF copies to `output/pdf/` and `docs/`, and identical text copies to `output/copy/` and `docs/`. Rebuilding resets visual QA to pending. The guide is a quick introduction, not an exhaustive manual or a claim that every receiving app accepts every drag type.

Five current assets were exported locally through `ExportGuide.swift` from the frozen Release Store-channel QA module: Projects, Captions (legacy `INBOX` filename), Search, Task and the canonical robot. The PDF uses Projects, Search and the robot; Captions and Task remain supporting excerpts. All fixtures are fictional and use an ephemeral archive with isolated preferences. No user captures, KARI material, personal clipboard, network requests, live app windows or notification delivery were used.

The selected source is `native/`, verified against the final-candidate source freeze. The module cache is `native/build/qa-cache/app-store-5013654b8c68f93cbaa913c1212168402be85ff94c7d33fca10d7e15c3e13e7e/`. Source inventory, Release configuration, channel flags, target and module/library hashes are checked before and after native rendering. The PDF builder independently verifies the same source, module, exporter and asset hashes.

Native provenance and accessibility anchors are in `assets/guide-native-source-manifest.json` and `assets/guide-native-renders.json`. `assets/guide-assets.json` records crop/callout positions measured against the current images; leaders were repaired to avoid native label text. The final PDF page render is `tmp/pdfs/guide-0.4.41-96-render-2/`. Its structural layout receipt is `tmp/pdfs/robot-guide-layout-check.json`; structural checks alone are not visual approval.

## Regeneration

Use the bundled workspace Python/ReportLab/pypdf runtime and Poppler paths in the local review workflow. Provide the selected version/build, source and module explicitly. Coordinate native rendering with GUI QA; the fixture uses non-key offscreen windows and may require scoped access to native macOS window services. It never launches or installs DaBin.

Run the PDF artifact marker once immediately before the first authoring command for a new operation. Do not repeat the marker during repairs of that operation. Render and inspect both final pages at original resolution after each meaningful layout repair. Record the exact PDF hash, actual page findings and current asset/source provenance in the versioned guide receipt only after inspection. Do not rewrite old version numbers or hashes to bless stale assets.

## Preservation and limits

The previous 0.4.31 guide inputs, native assets, PDF, friendly copy and metadata remain under `archive/guide-before-0.4.41-20261005/`. All 15 files were reverified against the preservation manifest. The previous App Store content pack remains separate with all 19 files byte identical. Earlier guide revisions remain in their own archives. [Package verification](../../docs/qa/full-review-2026-10-05/review-pack-final-verification.json) records this preservation and exact parity of the current PDF copies.

Screenshots reflect current native Store-module views, not an accepted distribution-signed Store app. Physical cross-application/browser drop completion and a second monitor remain untested in the final campaign. Dragging instructions concern destinations that accept the content. Auto Capture is off by default; screenshot-folder capture does not record the live screen. This artifact work changes no production native source or personal archive and performs no upload, submission or account action. The separately completed local direct-app installation is documented in its own verification receipt.
