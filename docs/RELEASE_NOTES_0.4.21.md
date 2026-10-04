# DaBin 0.4.21 (76): the robot opens your workspace

The full-view transition is now a small character performance. The robot prepares, moves into a larger readable pose, brings its hands forward and opens the workspace. Closing gathers the view back into the same robot before it coils and returns to its island or corner.

- The island and transition share the original metallic chest, neck, intake and feet, as well as the existing shared face. The face keeps its proportions throughout; the old tall split-panel body is gone.
- Opening takes 1.10 seconds and closing takes 0.96 seconds. The face and hands remain readable while the workspace fades in or out. All tracks use one animation clock.
- Reopening during a close resumes from the currently drawn position, shape and opacity. Closing during the entrance does not flash hidden content. Generation-based cancellation prevents old callbacks from finishing a newer transition.
- Opening while the island robot is still arriving starts at its visible position, not its travel endpoint. Normal and mirrored perches retain their exact artwork alignment; interaction targets keep their existing size.
- A padded native stage gives outlines and hands room to move. Hosted content stays at its final size, without per-frame SwiftUI layout. Controls cannot activate at invisible final coordinates during the transition.
- Quiet mode and macOS Reduce Motion retain the short 0.14-second static fade. No sound, capture, archive, search or notification behavior is intentionally changed.

## Verification and local installation

**0.4.21 (76) is installed and running locally.** The app quit normally before guarded replacement; the previous 0.4.20 bundle was backed up. Strict signatures, version, embedded source fingerprint and both executable hashes match the Release receipt. Live Settings confirms the version, tooltips enabled, Auto Capture paused and Quiet mode off. Expand, close, Escape, reopen and restore controls were exercised; Settings was retained after reopening and the original Inbox was restored. No capture was opened, copied or edited for verification. The installer changes only app bundles; the personal archive was not independently byte-inventoried.

Eleven selected Release suites have current passing evidence across two runs: ten unchanged suites in the [window/artwork run](../native/build/qa/runs/20261002T074947795986Z/report.json), plus the corrected visual fixture's [final passing run](../native/build/qa/runs/20261002T075326750725Z/report.json). The first report's overall failure belongs to the superseded visual test, not those ten accepted suites. All accepted test and production inputs match current files. The final visual suite passes **1,359 checks**, with eight real native opening/closing MP4s covering compact/expanded light/dark fixtures, exact-source artwork, uniform head scale, unchanged rail masks, shared timing, moving/mirrored handoffs, late/mid-motion reversals, early cancellation and once-only cleanup. This is scoped motion verification, not another full 75-suite search run.

The review uses native presentation-layer frames with fictional archives, not generated mockups or personal captures. Compact recordings have maximum sample gaps below 38ms. Expanded opening readback costs about 131ms and its observed gap reaches 134ms; expanded closing gaps stay below 96ms. These CPU recordings are **not a live compositor FPS measurement**. Expanded opening gaps are accepted only when explained by measured CPU readback plus 25ms, with an absolute 180ms ceiling; compact opening and all closing retain the 120ms cap. Frame/change minimums, exact 2× resolution and direct real-time motion assertions remain unchanged. Late reversal now observes the actual fading presentation in one bounded animation instead of relying on a fixed sleep. Earlier failures remain diagnostic evidence.

Build/source inventory, deterministic project, whitespace and 13 offline metadata-draft checks pass. This local ARM64/macOS 26.6.2 verification does not establish minimum-OS compatibility or distribution approval. Native live screenshots were blank with window capture exclusion active, so visual approval uses the fictional native renders. See the [exact verification receipt](qa/robot-motion-0.4.21-2026-10-02/verification.json). No Git push, public binary release or App Store submission was performed.

## Actual animation previews

- [Opening — compact, light](../native/build/qa/robot-close-visual/57048286-EA03-48C8-8AE7-1273F04CA12D/DaBin-Robot-Open-380x500-light@2x.mp4)
- [Closing — compact, light](../native/build/qa/robot-close-visual/57048286-EA03-48C8-8AE7-1273F04CA12D/DaBin-Robot-Close-380x500-light@2x.mp4)
- [Opening — expanded, dark](../native/build/qa/robot-close-visual/57048286-EA03-48C8-8AE7-1273F04CA12D/DaBin-Robot-Open-1200x800-dark@2x.mp4)
- [Closing — expanded, dark](../native/build/qa/robot-close-visual/57048286-EA03-48C8-8AE7-1273F04CA12D/DaBin-Robot-Close-1200x800-dark@2x.mp4)
