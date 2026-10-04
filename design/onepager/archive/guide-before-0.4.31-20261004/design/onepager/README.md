# DaBin robot-led quick guide

Final PDF: [DaBin Quick Guide](../../docs/DaBin-Quick-Guide.pdf). Reusable copy: [DaBin Friendly Copy](../../docs/DaBin-Friendly-Copy.txt). These tracked copies remain available from Git; generated `output/` files are local-only.

The guide is two A4 landscape pages, written in the robot's friendly voice. Page one introduces DaBin and points out projects, the three main views, search and file previews on the real interface. Page two explains three small habits: saving something, keeping a project together and focusing on one task. Optional Auto Capture and comfort settings are kept separate from the first steps.

`copy.json` is the shared source for the PDF and the text copy. This is a quick introduction, not an exhaustive feature inventory. It uses the current Quiet Orbit robot and real native UI with fictional examples. No personal archive, real clipboard, live installed-app screens or KARI material is used. This documentation update does not change app buttons or settings.

## Rebuild

1. If native UI sources changed, run `export_guide_assets.py` on the Mac. It requires a current, hash-verified Release QA module and exports isolated fictional views through `ExportGuide.swift`. It rejects stale module inputs or sources changed during export. It does not launch or update the installed app.
2. Edit `copy.json`; use `assets/guide-assets.json` for annotated UI targets and PDF-only crop coordinates. Do not paint over the native screenshots.
3. Run `build_guide.py` with Python, ReportLab and pypdf. It embeds the Mac's Arial regular/bold fonts, writes the delivery PDF and text copy, and synchronizes the identical PDF to `../../docs/DaBin-Quick-Guide.pdf`. Keep `../../docs/DaBin-Friendly-Copy.txt` identical to the generated text copy when updating the copy. Previous PDF contents and the earlier builder are preserved under `archive/`.
4. Render both pages with Poppler at 150 dpi or higher, inspect every page for clipping, alignment and readability, then record the reviewed PDF hash in `qa/`. Structural/content checks are written to `../../tmp/pdfs/robot-guide-layout-check.json`; rebuilding correctly resets visual review to pending.

Native asset provenance lives in `assets/guide-native-source-manifest.json`; measured UI anchors and fixture details live in `assets/guide-native-renders.json`. The final review record is [robot-guide-2026-10-02.json](qa/robot-guide-2026-10-02.json).
