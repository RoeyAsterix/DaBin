# DaBin local review asset workflow

The scripts prepare local App Store copy, fictional native screenshots, the customer Quick Guide and a versioned content pack. They do not upload, submit, publish, sign or change account declarations. Candidate version and build come from the selected native source; explicit arguments make a mismatch fail before authoring. The completed local review draft targets **0.4.41 (96)** and the bundled policy **Updated 5 October 2026**, with production locked by the final-candidate source freeze. The final Release app-store QA run passes 125 of 126 suites with unchanged inputs; strict zoom timing fails the unchanged 50 ms input-to-layout and 33 ms steady-timer budgets at p95 51.3154 ms and 61.2394 ms respectively. The original unsampled 600-second workload completed, with p95 input 53.6320 ms and steady timer 63.0316 ms still above those budgets. The unsigned compile/preflight, completed XCTest readback, fresh temporary sandbox rerun and four privacy image inspections passed their respective scopes. Their separate receipts preserve the original coordinator's collector/FileProvider failures. The three current screenshots, five guide assets, 15-page submission document and two-page Quick Guide were rendered and visually inspected after the coordinated asset stage was released. The document builder reads the selected bundled policy directly; it never reuses the old pack’s policy. The public policy currently serves the older 4 October text despite HTTP 200, so publication and exact parity remain pending.

Use the bundled workspace runtime. Native fixture exports must wait until all coordinated GUI QA has finished. Select an exact source-matched Release **app-store** module cache. Both source and module hashes are checked; source/resource changes during export invalidate the output. Fixture compilation and temporary resource copies use `tmp/app-store-assets/`, rather than altering native source inputs.

The previous 0.4.31 pack and screenshots remain unchanged. Earlier builder sources are in `archive/0.4.31-86/`. Previous guide inputs, native assets, PDF, friendly copy and metadata are backed up under `../onepager/archive/guide-before-0.4.41-20261005/`. Do not run archived builders as current tools.

## Runtime and selected inputs

Run from the DaBin project root. Exact selected paths, hashes, failed QA/performance summaries, supplemental receipt hashes, executed argument arrays and final output hashes are recorded in [review-pack-authoring-plan.json](../../docs/qa/full-review-2026-10-05/review-pack-authoring-plan.json). Both artifact-operation markers ran exactly once; repair iterations reused the same operation. The final [package verification](../../docs/qa/full-review-2026-10-05/review-pack-final-verification.json) checks all ZIP entries, exact source copies, module hashes and preservation. The [all-page visual receipt](../../docs/qa/full-review-2026-10-05/review-pack-final-visual.json) records the actual final DOCX and guide render pages. Recheck later coordinated results before a new authoring operation. The 30-second and 600-second timing results are synthetic native measurements; physical input-to-display and external drop acceptance remain separate.

```bash
DABIN_PYTHON='/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
DABIN_NODE='/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node'
DABIN_DOC_MARKER='/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime/plugins/documents/skills/documents/container_tools/mark_artifact_operation_started.mjs'
DABIN_PDF_MARKER='/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime/plugins/pdf/skills/pdf/container_tools/mark_artifact_operation_started.mjs'
DABIN_NATIVE='/absolute/path/to/selected/native'
DABIN_MODULE='/absolute/path/to/selected/native/build/qa-cache/verified-cache'
DABIN_QA_REPORT='docs/qa/the-actual-final-run/README.md'
```

`render_document.py` invokes the Documents skill's `render_docx.py` and forces bundled headless LibreOffice at `/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/MacOS/soffice`. It never falls back to desktop LibreOffice. Poppler is also selected from the bundled runtime.

## Fictional screenshots

After QA finishes, create the new screenshot set:

```bash
"$DABIN_PYTHON" design/app-store-pack/export_screenshots.py --render --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE"
```

The fixture uses its own temporary archive, isolated preferences, blocked clipboard providers and notification client, previews off and non-key offscreen windows. It does not read personal captures, KARI material, the live clipboard or another app's windows. The native controls are actual production views; only the backdrop and marketing captions are composed around them. Output is three opaque RGB 1440 × 900 PNGs plus source/resource/module provenance.

Open all three images at their original resolution. Check current compact controls, captions, readability, card bounds and artwork. Record `visualReview` beginning with `PASS` in the screenshot manifest only after that inspection. The exporter refuses a nonempty output directory. For a repair, choose a new `--output-dir` and pass that same directory to the subsequent document and packaging scripts. Final comparison with the exact distribution-signed app remains pending.

## Quick Guide

Export current native guide views after QA, then inspect all five source PNGs and their accessibility anchor manifest:

```bash
"$DABIN_PYTHON" design/onepager/export_guide_assets.py --render --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE" --distribution app-store
```

Update `design/onepager/assets/guide-assets.json` crop/callout coordinates against new views whenever regenerating. Its current coordinates were measured against the build 96 native views and inspected in both final PDF pages. The old assets remain preserved in the guide archive.

Immediately before the first PDF authoring command, run the PDF artifact marker **once for this operation**, then build:

```bash
"$DABIN_NODE" "$DABIN_PDF_MARKER" --operation-kind edit --expected-output-count 1 --output-format pdf
"$DABIN_PYTHON" design/onepager/build_guide.py --build-pdf --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE"
'/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/poppler/bin/pdftoppm' -png -r 160 docs/DaBin-Quick-Guide.pdf tmp/pdfs/guide-0.4.41-96
```

Inspect both rendered pages after each meaningful repair. The guide builder checks native/source/module hashes, required instructions and layout bounds. Its generated `tmp/pdfs/robot-guide-layout-check.json` is a structural receipt, not visual approval. After inspecting both pages, retain a versioned receipt at `design/onepager/qa/robot-guide-0.4.41-96.json` with the same current `version`, `build` and `pdf_sha256`, `result: "PASS"`, and the actual all-page visual findings. Packaging requires that receipt. The stable PDF and text copies are updated only by this verified build operation.

## Submission document

Immediately before the first DOCX authoring command, run the Documents marker **once for this operation**:

```bash
"$DABIN_NODE" "$DABIN_DOC_MARKER" --operation-kind create --expected-output-count 1 --output-format docx
"$DABIN_PYTHON" design/app-store-pack/build_content_pack.py --build-docx --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE" --qa-report "$DABIN_QA_REPORT" --prepared-date '6 October 2026' --apple-audit-date '5 October 2026'
"$DABIN_PYTHON" design/app-store-pack/render_document.py docs/app-store/submission-pack-0.4.41-96/DaBin-App-Store-Content.docx --output_dir design/app-store-pack/qa/0.4.41-96/render-1 --emit_pdf
"$DABIN_PYTHON" design/app-store-pack/verify_content_pack.py --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE" --render-dir design/app-store-pack/qa/0.4.41-96/render-1
```

The prepared date is 6 October 2026 locally; the latest official-source verification is dated 5 October 2026 UTC. The policy remains Updated 5 October 2026. The Apple audit date is the date references were actually checked, not the document creation date. Change it only after a new official-source review. QA and performance statuses default to pending. Set --qa-status or --performance-status to failed with the corresponding --qa-summary or --performance-summary when documenting an actual failure. Repeat --known-issue for unresolved integration issues. A passed status requires an existing --qa-report evidence file; do not use it for an earlier source or infer performance acceptance from a verified production module. The document and package always retain submissionReady false and include remaining release gates.

The builder preserves the established document styles: black title/headings, portrait listing/review/privacy sections, landscape screenshot pages, readable tables and repeating table headers. Counts are derived from current text rather than literals. Support and owner placeholders remain explicit.

Open **every** `page-N.png` at original resolution. Repair clipping, overlap, unexpected page breaks, tables or unreadable images before delivery. Rebuild with `--replace-draft` only for this candidate and render into a fresh directory. Do not rerun the artifact marker during repair iterations of the same creation operation. After actual all-page inspection, rerun verification with `--inspected-pages` listing every verified page number and `--write-receipt`; this creates the versioned document receipt and records completed review in the authoring snapshot. The verifier checks exact public fields, review notes, full bundled policy body and original embedded screenshot hashes. The current final DOCX render is `qa/0.4.41-96/render-4/`; all earlier render and failure evidence remains retained.

## Package after visual approval

```bash
"$DABIN_PYTHON" design/app-store-pack/package_content.py --package --version 0.4.41 --build 96 --native-root "$DABIN_NATIVE" --module-cache "$DABIN_MODULE"
```

The package builder requires current source-matched screenshots, matching bundled policy, DOCX source-parity/all-page approval and guide approval. It creates a new versioned ZIP, verifies ZIP integrity and each file hash, and preserves prior versions. No owner field is invented. Public support/policy parity, distribution signing and validation, signed fresh-install/upgrade acceptance, device/OS/VoiceOver/energy/IPv6 checks and Apple review remain separate release gates.
