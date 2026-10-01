# DaBin 0.4.14 (69) - coordinated robot closing

The robot now folds inward, reforms as a compact character, coils briefly and shrinks back toward the island or screen-corner home with a final tuck and fade. The full close lasts 0.78 seconds; opening remains 1.15 seconds. Reduce Motion keeps the existing 0.14-second static fade without travel.

The previous content transform and opacity shared an animation key, so the fade replaced the shrink. They now have independent keys and follow the same body geometry as the frame strokes. The metallic shell fills gradually as the content contracts instead of abruptly replacing the transparent perimeter. Reopening mid-close preserves the presented transforms, individual part opacities and torso-mask paths. The native hosted content stays mounted at its final size; there is no per-frame SwiftUI resizing, screenshot proxy or extra transition window.

This candidate includes the existing tooltip preference, removal of manual add-paste controls, consistent robot artwork, capture timestamps, original-file preview opening and performance improvements.

## Verification and local deployment

All **20/20 selected Release suites** pass, including 372 actual closing-motion, mask/opacity reversal, cleanup and MP4 encode/decode checks across compact/expanded light/dark fixtures. Native controller tests also exercise the real expanded safe-area panel, duplicate closes, Command W, interrupted opening, display reconfiguration and late reopening. Build and QA input hashes match the frozen sources; the generated project and whitespace checks pass.

**0.4.14 (69) is installed and running locally.** The current app exited normally; the guarded installer backed up 0.4.13 before replacement and did not modify the archive. The installed app and helper match their Release receipt, and the bundle passes strict signature verification. Live Settings confirms the version; the expanded 1512 × 949 board closes to a hidden endpoint while the process stays running, reopens successfully and returns to the previous compact Inbox view. Capture and theme preferences were not toggled.

[Installation evidence](qa/local-install-0.4.14-2026-10-01/verification.json), [final selected QA report](../native/build/qa/runs/20261001T191414888807Z/report.json), [expanded light animation preview](../native/build/qa/robot-close-visual/767F0848-06EE-45CF-A4BC-1E35B2EA27F9/DaBin-Robot-Close-1200x800-light@2x.mp4), [compact light animation preview](../native/build/qa/robot-close-visual/767F0848-06EE-45CF-A4BC-1E35B2EA27F9/DaBin-Robot-Close-380x500-light@2x.mp4).

The previews use actual production presentation layers and fictional content, not personal desktop recordings. Expanded 2x CPU capture has roughly 0.10-second sample gaps; these files verify choreography, not the live GPU frame rate. This is scoped native verification, not a new complete distribution review. No public release has occurred. The separate two-second-message request remains unidentified and is not changed by this animation work.
