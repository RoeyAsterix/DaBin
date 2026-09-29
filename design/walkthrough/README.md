# DaBin application walkthrough

**Version scope:** this delivered tour records DaBin **0.3.19 (46)**. The app has since moved to the 0.4.0 interface. The [archived MP4](../../docs/walkthrough/DaBin-0.3.19-App-Walkthrough-59s.mp4) remains the verified delivery. Regenerating UI assets against 0.4.0 requires updating the scene/control coordinates and reviewing the new edit; the old coordinates must not be assumed to match the redesigned header.

A 59-second, 1920 × 1080, 30 fps walkthrough of the production macOS views. The app is the main subject throughout. A small production robot, brief speech bubbles, local voiceover, cursor movement and click rings guide a single fictional `Launch-plan.pdf` from capture to export.

## Authored sources

- `build_walkthrough.js`: native Higgsedit composition; exact app images, timed actions, guide, speech and audio. UI controls are never redrawn.
- `assets/Launch-plan.txt`: fictional PDF content. The phrase **launch checklist** occurs inside the generated PDF, so Search demonstrates real document indexing.
- `assets/narration.json`: twelve short voice/bubble lines and their timing.
- `generate_narration.py`: offline macOS Samantha speech generation and audio validation.
- `../../native/Tests/WalkthroughRenderTests.swift`: isolated production renderer and assertions; never linked into DaBin.
- `../../native/scripts/render_walkthrough.sh`: compile/render entry point.
- `render_local.mjs`: local composition adapter for environments without the Higgsedit executable. Uses public Canvas and FFmpeg libraries, not a copied editor runtime.
- `inspect_video.swift`: AVFoundation metadata, exact-time frame/contact-sheet extraction, and full media decode verification.

No production app behavior changes are needed. Existing unrelated repository edits are preserved.

## Generate the production assets

From the repository root on macOS with Xcode installed:

```sh
bash native/scripts/render_walkthrough.sh
python3 design/walkthrough/generate_narration.py
python3 design/walkthrough/generate_narration.py --check
```

The native renderer uses a temporary archive and UserDefaults suite, disables networking and notifications, never reads the general clipboard, and deletes its temporary archive on exit. It verifies PDF import/text extraction, an indexed-only query match, three active Weekly dates, saved comment, task conversion/completion, day export and archive reopening. Assets and a manifest are generated in `native/build/qa/walkthrough/`; voice clips are in `native/build/qa/walkthrough-audio/`.

The standard production release render can also be run:

```sh
cd native
./scripts/render_qa.sh --release-ui
```

That release gate requires a physical Retina backing surface. On the available 1× display it stops as designed. The walkthrough renderer uses its own isolated 2× offscreen window, with no changes to the release gate or production app.

PDFKit tiled pages are absent from AppKit's `cacheDisplay` output. The test renderer restores only the real fixture page, drawn by PDFKit at the live PDFView's measured page bounds. Surrounding UI is untouched.

## Preferred Higgsedit build

When the native Higgsedit CLI is installed, run from the repository root:

```sh
higgsedit build design/walkthrough/build_walkthrough.js
higgsedit check native/build/DaBinAppWalkthrough
higgsedit sheet native/build/DaBinAppWalkthrough \
  --times 2,6,9.5,12,16,21,30,35.8,39.5,43.8,48,53.5,57 \
  --cols 3 --out output/video/DaBin-App-Walkthrough-contact-sheet.png
higgsedit render native/build/DaBinAppWalkthrough \
  --quality final --depth 8 --bitrate 12M \
  --out output/video/DaBin-App-Walkthrough-59s.mp4
```

The source supports `DABIN_REPO_ROOT`, `DABIN_WALKTHROUGH_ASSETS`, `DABIN_WALKTHROUGH_AUDIO`, and `DABIN_VIDEO_PROJECT_DIR` overrides. Generated projects remain in ignored `native/build/`.

## Local render fallback used for this delivery

Higgsedit was available only in a remote sandbox. Its upload tool could not take generated local assets through the permitted attachment route, and automatic approval review rejected exporting its private runtime. No private runtime was copied. The local adapter evaluates the same authored composition and validates media, timing and scene coverage before producing the MP4.

Prerequisites: Node, `@napi-rs/canvas`, and FFmpeg. In this workspace Canvas is supplied by the bundled dependency runtime; a public FFmpeg binary is installed in ignored `native/build/walkthrough-tools`:

```sh
python3 -m pip install --target native/build/walkthrough-tools imageio-ffmpeg
export DABIN_FFMPEG="$PWD/native/build/walkthrough-tools/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1"
node design/walkthrough/render_local.mjs check
node design/walkthrough/render_local.mjs sheet \
  --times 2,6,9.5,12,16,21,30,35.8,39.5,43.8,48,53.5,57 \
  --cols 3 --out output/video/DaBin-App-Walkthrough-contact-sheet.png
node design/walkthrough/render_local.mjs render
```

The exact local runtime paths and measured results for the delivered render are recorded in `QA.md`.

## Verify the encoded output

```sh
swift -module-cache-path /tmp/dabin-walkthrough-swift-cache \
  design/walkthrough/inspect_video.swift \
  output/video/DaBin-App-Walkthrough-59s.mp4 \
  output/video/DaBin-App-Walkthrough-QA \
  --times 2,6,9.5,12,16,21,30,35.8,39.5,43.8,48,53.5,57 --decode
bash native/scripts/test.sh \
  --only LocalContentSearchTests --only CaptureTaskConversionTests \
  --only DayExportTests --only DayExportUITests --only WeeklyStateTests
git diff --check
```

Inspect the decoded MP4 frames as well as the composition contact sheet. Check query/snippet readability, PDF continuity, comment/task changes, off-default Auto Capture, local archive text, all four export choices, full bubbles and uncovered controls.

## Scene map

| Time | Visible action and evidence |
| --- | --- |
| 0–4 | Real Daily board, small robot entrance, fictional PDF ready to drag |
| 4–11 | PDF cursor drag, hungry/digest/success robot poses |
| 11–18 | Saved PDF in Daily, Files filter removes the unrelated note |
| 18–25 | Weekly opens three active dates; Search Week menu |
| 25–33 | Typed `launch checklist`; actual indexed PDF match |
| 33–42 | PDF detail; comment added and saved; task converted and completed |
| 42–49 | Settings: Auto Capture off; local archive/search explanation |
| 49–55.6 | Real Weekly export popover: copy/download day and week |
| 55.6–59 | Return to populated Daily and completed PDF task |

## Honest scope

This is an editorial walkthrough between verified production states, not a continuous screen recording. Cursor drag, typing, scrolling, popover placement and transitions are reenacted; the views, indexed result, saved changes and exported fixture text are real. The guide uses the app's robot poses with editorial movement. Export choices are shown without writing to the user's clipboard or triggering an installer/download dialog. All on-screen content is fictional. The voice is macOS Samantha, not a custom character voice. The concise robot bubbles also serve as captions. The local adapter uses Arial for guide text when DM Sans is absent; the production UI fonts are preserved exactly in the native images.
