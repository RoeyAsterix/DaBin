# Persistent project recording sign — 3 October 2026

DaBin 0.4.24 (79) is installed locally. The robot holds a project board with fixed **10-point project text** while Auto Capture is enabled at a named project. Pointer departure no longer hides it. Disabling both channels removes the board; Paused retains the board with its status. Opening the main window transfers the label to its reserved chrome, and the task timer includes it in its held board.

All **11 selected Release suites passed** with zero failures and unchanged inputs during the run. The two new suites contribute 31 controller checks and 53 native rendering checks. [Native report](native-report.json), [verification record](verification.json), [installation evidence](installation.json).

Live accessibility verified `Capturing to: Tester Uno` in the expanded frame and `DaBin purple robot, capturing to Tester Uno` after the frame closed. Pausing changed the label to `Paused: Tester Uno`; the original paused preference was restored. The native panel requests exclusion from window capture, so a live screenshot returned a white image. Capture exclusion was preserved; the native fixtures below provide visual evidence.

- [Corner robot holding the board](renders/corner-recording@2x.png)
- [Paused board](renders/corner-paused@2x.png)
- [Long project name at 10 points](renders/corner-long-title@2x.png)
- [Camera-island recording position](renders/orbit-bottom@2x.png)
- [Expanded window](renders/full-board-recording@2x.png)
- [Task timer board](renders/timer-recording@2x.png)

The installed bundle has source fingerprint `a888d106326a2bf3a09660f1b338b10408cb04a564b23f03af473d77a3341096`; its main/updater hashes and strict signature were verified. A later unrelated build replaced the shared build receipt. The [reconstructed input attestation](build-attestation.json) combines 119 retained QA input hashes with 21 script/updater hashes from that later receipt and reproduces the signed installed fingerprint exactly. It is labeled as a reconstruction, not an original build receipt.

Nine unrelated production views changed after this feature's build. They were preserved, and the feature sources still match the tested snapshot. This record does not validate those subsequent changes or claim a complete 79-suite regression. Tests ran on ARM64 macOS 26.6.2 with SDK 27; minimum-OS runtime and signed-distribution validation remain outside this feature check. Personal captures were not opened, copied or edited for verification, and the personal archive was not independently byte-inventoried.
