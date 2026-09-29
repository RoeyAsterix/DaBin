# DaBin island playground — 29 September 2026

Local candidate **0.4.0 (48)**. Built and visually reviewed; **not installed or published**.

[Watch the 14.4-second native preview](DaBin-Island-Playground.mp4) · [20 sampled encoded frames](encoded-qa/contact-sheet.png)

## Behavior

- Hands hook onto the physical camera island, lower the body, and stay attached during movement.
- Capture styles select a one-handed snack swing, a slip-and-catch, or a sideways ledge shuffle. The robot pulls up afterward; one hand gives a last wave.
- Idle invitations look out upside down. Manual reveal settles into a supported hang with pointer-following eyes.
- A 232 × 150 transparent stage gives the motion room. A central 128 × 130 click/drop target remains stable; surrounding margins pass through to other applications. Opening the board starts from the central body rather than the entire stage.
- No artificial island housing is drawn. The stage's top boundary matches the physical housing's underside. External displays keep the compact corner fallback.
- Existing reaction rotation, exact burst counts, interruption, Quiet mode, and Reduce Motion behavior remain. Valid display changes replan only unfinished capture feedback.

## Evidence

The preview runs the production native character and choreography, samples its live Core Animation presentation layer at 30 fps, and shows the same sample at actual scale and 2×. The laptop/desktop background is fictional. It does not record the user's screen or contain capture contents. All 431 encoded frames decoded successfully with monotonic timestamps. Peak swings, slips, sideways travel, upside-down waving, hand contact, and exits were visually reviewed. There is no added editorial robot motion.

Both the optimized standalone ARM64 build and the Xcode Release build passed. The standalone build's strict signature check passed. [Build receipt](build-receipt.json) records source and executable hashes; all inputs were rechecked after packaging. Distribution signing and App Store validation are separate.

The unchanged-source targeted regression run passed **8/10 suites**:

| Suite | Result |
| --- | --- |
| Quick access | 10 checks passed |
| Automatic-capture presenter | 67 checks passed |
| Automatic-capture renderer and reactions | 1,551 checks passed |
| Robot motion | 40 checks passed |
| Island choreography | 38,481 checks passed |
| Robot lifecycle | 38 checks passed |
| Robot application frame | 31 checks passed |
| Robot drop destination | 92 checks passed |
| Native windows | 145/147 checks passed; hover keyboard-focus and return-focus checks failed |
| Robot window transition | Failed actual-window-visibility check after staging cleanup |

[Full targeted report](regression-report.json) · [Window failure log](WindowTests.log) · [Transition failure log](RobotWindowTransitionTests.log)

The Mac was locked during these runs, and computer-use inspection confirmed it could not be unlocked automatically. These three focus/visibility failures remain failures requiring an unlocked-session rerun; the overall GUI validation is not green. Earlier work-inbox GUI checks also remain recorded in the [preceding QA record](../work-inbox-2026-09-29/README.md). This targeted run does not claim to rerun every suite.

## Installation status

The guarded installer refused to replace a running DaBin process. The new candidate has not opened the user's live archive. The existing installed/running app and archive remain in place. Unlocking the Mac is required to inspect drafts, quit DaBin normally, preserve the archive before the first updated launch, install the verified candidate with the existing app backup, and verify the physical island and GUI checks. The manual robot's existing placement preference is preserved; **Settings → Below camera island** selects the island home.

Machine-readable status: [delivery-status.json](delivery-status.json).
