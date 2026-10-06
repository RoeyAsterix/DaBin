# DaBin robot-led quick guide

The updated [DaBin Quick Guide](../../docs/DaBin-Quick-Guide.pdf) and [Friendly Copy](../../docs/DaBin-Friendly-Copy.txt) describe **0.4.31 (86)**. The PDF preserves the friendly Quiet Orbit robot voice and two A4 landscape pages. Page one introduces the current project workspace, global Search, export and Finder. Page two gives the native date-column Search view a wide, readable panel, followed by saving/dragging, new tasks and colored priorities, optional Auto Capture, and moving between monitors.

`copy.json` is the shared copy source. `build_guide.py` writes identical PDF copies to `output/pdf/` and `docs/`, and identical text copies to `output/copy/` and `docs/`. Rebuilding resets visual QA to pending. The guide is a quick introduction, not an exhaustive manual or a claim that every receiving app accepts every drag type.

## Verified native assets

The five current assets were exported locally from the frozen 0.4.31 Store-channel QA module through `ExportGuide.swift`: Projects, Inbox, Search, Task and the canonical robot. The delivered PDF uses Projects, Search and the robot; Inbox and Task remain available as supporting native excerpts. All fixtures are fictional, in an ephemeral archive with isolated preferences. No user captures, KARI material, actual clipboard, network requests, live app windows or notification delivery were used.

The frozen source is explicitly selected at:

`native/build/store-preparation-20261004/native`

This is intentional: separate unverified tutorial edits in the shared `native/Sources/DaBin` tree are excluded. `export_guide_assets.py` accepts an explicit `--native-root`, `--module-cache` and `--distribution`; it requires a matching Release receipt, full source inventory/hashes, channel flags, target, and module/library hashes. It rechecks source, resource and Info hashes after rendering. The PDF builder independently checks the same frozen inputs, receipt, binary outputs, exporter and asset hashes. It does not silently fall back to stale artwork or disable source checks.

## Rebuild

From the repository root, using the bundled Python with ReportLab and pypdf:

```sh
python3 design/onepager/export_guide_assets.py \
  --native-root native/build/store-preparation-20261004/native \
  --module-cache native/build/store-preparation-20261004/native/build/qa-cache/app-store-34dd658724d8a131934a15dd329a81843c7c8c7af3aad201a34ea2bf28acde4a \
  --distribution app-store
python3 design/onepager/build_guide.py
pdftoppm -r 180 -png docs/DaBin-Quick-Guide.pdf tmp/pdfs/robot-guide-0.4.31
```

Coordinate native rendering with other GUI QA. It uses its own non-key offscreen windows and may require scoped host access to native macOS window services. It never launches or installs DaBin. When changing the source/version, provide the newly verified source and cache explicitly and re-render; do not rewrite hashes to bless stale assets.

Inspect both rendered pages at original resolution, then update the [final QA record](qa/robot-guide-2026-10-04.json). The measured layout record is `tmp/pdfs/robot-guide-layout-check.json`. Native provenance and anchors are in `assets/guide-native-source-manifest.json` and `assets/guide-native-renders.json`. `guide-assets.json` contains PDF-only clipping and callout positions; no native pixels are painted over.

## Preservation and scope

The previous 0.4.19 PDF, copy, source scripts and asset set are preserved with checksums under `archive/guide-before-0.4.31-20261004/`; older archived PDFs remain intact. This documentation update changes no production application source, installed app or user archive.

The screenshots reflect the verified native Store module, not a final distribution-signed sandbox upload. This guide does not establish physical drop completion in every external app, an App Store approval, or availability in the Store. Dragging is described only for destinations that accept the content. Auto Capture is off by default; the header's dot grows while running and animates unless Reduce Motion is enabled. Screenshot-folder capture does not record the live screen.
