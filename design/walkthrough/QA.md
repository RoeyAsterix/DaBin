# DaBin application walkthrough — QA

Verified on 29 September 2026 against the working production sources reporting DaBin 0.3.19 (46).

## Delivered output

- `output/video/DaBin-App-Walkthrough-59s.mp4`
- `output/video/DaBin-App-Walkthrough-contact-sheet.png` — frames extracted from the encoded MP4
- `output/video/DaBin-App-Walkthrough-QA/` — exact-time frames, metadata, composition/temporal checks, production-render manifest, app test report and audio measurement

| Measured property | Result |
| --- | --- |
| Duration | 59.000 seconds |
| Picture | 1920 × 1080; H.264/AVC; YUV 4:2:0 |
| Frame rate / frames decoded | 30 fps / 1,770 |
| Audio | AAC, stereo, 48 kHz; twelve local Samantha voice clips |
| Full decode | Video and audio completed; presentation timestamps monotonic |
| File size | 1,877,109 bytes |
| Playback | AVFoundation reports playable and exportable |
| UI coverage | Continuous 0–59 seconds; approximately 67.7% of frame area |
| Robot area | Approximately 1.8% of frame |
| Speech overlap | None; last voice finishes at 57.444 seconds |
| Encoded audio peak | −5.2 dBFS; non-silent, no clipping |

MP4 SHA-256: `d1248ac56339f466ad1625f75e29e83cacb474a36fb2227c45e3498e452a5a62`.

## Commands and results

1. `bash native/scripts/render_walkthrough.sh` — **PASS**. Compiles production sources plus the isolated renderer with warnings treated as errors. Produces 31 production UI/robot assets. Verifies actual PDF import, PDFKit extraction, indexed-only query match, three active weekly dates, comment save, task conversion/completion, day export, and persistence after archive reopen.
2. `python3 design/walkthrough/generate_narration.py --check` — **PASS**, twelve non-silent clips, all within their bubble windows. Full regeneration also passed into a separate ignored QA directory.
3. `node --input-type=module --check < design/walkthrough/build_walkthrough.js`, `node --check design/walkthrough/render_local.mjs`, and Python compilation — **PASS**.
4. `node design/walkthrough/render_local.mjs check` — **PASS**, 65 visual layers, twelve audio clips, valid media and animation timing, no text-height overflow.
5. `node design/walkthrough/render_local.mjs sheet` — **PASS**, all major beats visually inspected.
6. `node design/walkthrough/render_local.mjs render` — **PASS**, final quality H.264 CRF 18, medium preset, AAC and MP4 faststart.
7. `swift -module-cache-path /tmp/dabin-walkthrough-swift-cache design/walkthrough/inspect_video.swift output/video/DaBin-App-Walkthrough-59s.mp4 output/video/DaBin-App-Walkthrough-QA --times 2,6,9.5,12,16,21,30,35.8,39.5,41.4,43.8,48,53.5,57 --decode` — **PASS**. Full decode and fourteen exact-time frames inspected.
8. FFmpeg `volumedetect` on the encoded audio — **PASS**, mean −24.8 dBFS over the full video including deliberate silent intervals; peak −5.2 dBFS.
9. `bash native/scripts/test.sh --only LocalContentSearchTests --only CaptureTaskConversionTests --only DayExportTests --only DayExportUITests --only WeeklyStateTests` — **PASS**, 5/5 suites and 434 checks: search 90, task conversion 140, exports 36, export UI 30, weekly state 138. This is relevant selected coverage, not a new full-application QA cycle.
10. `git diff --check` — **PASS**. The unrelated untracked `design/onepager/build_guide 2.py` retains SHA-256 `2c07b1c4f86e7faa7250a69c99be66bc645868de6d2e7d85a1645aa73fad09c3`.

The bundled Node used here is `/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node`; Canvas is its bundled `@napi-rs/canvas`. FFmpeg 7.1 was installed from public `imageio-ffmpeg==0.6.0` into ignored `native/build/walkthrough-tools`. No private editor runtime was copied.

## Visual checks

The composition sheet and the actual decoded MP4 sheet cover capture/drag/digest/success, Daily, Files filter, Weekly, PDF search, saved comment, task conversion/completion, Auto Capture Off, local archive, export choices and final Daily. Full-resolution search, comment, Settings and export frames also received an independent second review.

The same fictional PDF is recognizable throughout. The typed query and indexed snippet are readable. Auto Capture is visibly Off. Local archive/search text supports the narration. The four real export choices are readable. There are no blank or robot-only scenes, ghosted text, overflowing bubbles, guide-covered controls, or personal data in the inspected frames. The production weekly date's ellipsis and ordinary scroll viewport boundaries remain faithful to the app.

## Scope and limitations

- Interactions are editorial reenactments between exact production states, not a continuous screen recording. The native app performed the underlying import/index/save/task/export operations in an isolated store.
- The real release renderer `./scripts/render_qa.sh --release-ui` was attempted and stopped because the attached display reports 1× backing. Its Retina gate was preserved. The separate walkthrough renderer uses an explicit 2× offscreen test window. PDF page tiles are restored from the actual fixture PDF at measured PDFView bounds.
- The Higgsedit CLI was available only remotely. Its tool route did not support uploading these generated local assets, and automatic approval review rejected exporting its private runtime. The independently implemented local adapter rendered the same authored source and ran equivalent composition, contact-sheet and encoding checks. The remote `higgsedit check/render` commands were not claimed as passing.
- Guide typography uses installed Arial when DM Sans is unavailable; production UI typography is unchanged. The robot uses native poses with editorial motion. Voice is local macOS Samantha.
- Visual review sampled all major beats and selected full-size frames; it did not inspect every transition frame or perform a subjective listening review. All frames/audio decoded and the final audio signal was measured.
- No production functionality, personal archive, clipboard, notification settings, installation or unrelated working-tree changes were modified for this video.
