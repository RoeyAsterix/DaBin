# DaBin 0.4.11 (66) - one consistent robot

The island robot is the visual authority. The full application frame now uses the exact same native head construction: angular metallic lavender shell, polygon visor, rectangular mint eyes, scanlines, forehead indicator, seams and mouth. The old rounded bin face, floating lid, handle and separate dark pupils are removed. The frame's shell, mechanical arms and feet use the matching metal/silver palette, and its head retains the canonical proportions during expansion.

Daily and weekly empty states host the same native island character rather than a legacy SVG and a separately drawn face. Their small sleepy movement remains visible-only; inactive and Reduce Motion states stay static, with cleanup when removed.

Content insets, transparency, pointer gaze, blink, resizing, click-through, transition timing and existing capture actions are preserved. Task-completion smiles use the same four-point mouth topology as the canonical idle expression so the native animation can interpolate safely. This candidate includes the pending preview-click and timestamp improvements from 0.4.9–0.4.10.

## Verification and local deployment

- Built optimized ARM64 Release 0.4.11 (66), with the embedded updater and strict signature verification on the build script's clean copy. The build receipt matches all current runtime inputs. Finder can reattach metadata to the Documents copy; the guarded installer verifies its clean staging copy outside that synced directory.
- [12/12 selected Release QA suites passed](../native/build/qa/runs/20261001T172128487782Z/report.json): robot motion, island choreography, automatic-capture reactions, lifecycle, native frame interaction, Quiet Orbit artwork, empty-state hosting, window transitions, update configuration, preview opening, timestamp presentation and visual consistency. This is scoped regression coverage, not a new full-suite or public-distribution certification.
- [106 visual-consistency checks](../native/build/qa/robot-visual-consistency/robot-visual-consistency-report.json) compare actual native head geometry, palettes and same-scale raster crops; task-smile keyframes; and the real application at 380 × 500 and 1200 × 800 in light and dark mode. Native appearance and rendered background pixels are checked, not just screenshot labels. The rendered fixtures were visually reviewed.
- 52 release UI renders passed, including compact and 2x samples. [Empty-state raster verification](../native/build/qa/screenshots/robot-empty-state-renders.json) detected 15,215 changed bytes during active sleepy movement and zero during inactivity. No user archive or clipboard content was used for these robot fixtures.
- Regenerated the Xcode project from the shared source inventory; `generate_project.py --check` and `git diff --check` pass. Xcode build/archive commands were not run.

The older installed 0.4.8 (63) session has not been replaced. Local installation and live verification remain pending a safe app exit or explicit permission to force-quit the unresponsive process; unsaved edits could otherwise be lost. This is not a public release.
