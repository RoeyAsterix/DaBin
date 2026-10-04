# DaBin 0.4.24 (79) — persistent project recording sign

The project sign previously belonged to the brief successful-save celebration, so it disappeared while Auto Capture was still enabled. The robot now holds a native project-name board throughout an enabled project capture session.

- Project names use fixed 10-point text. Long names wrap or truncate without shrinking; mirrored camera poses keep the text upright.
- Enabling Auto Capture with a named project displays the robot without waiting for a new save. Moving the pointer away no longer dismisses it. Disabling both capture channels removes the board; Unfiled has no named-project sign.
- Pausing retains the project board with a Paused label. Ready and permission-related states do not falsely claim active capture.
- The expanded robot frame retains a compact project board in its existing top chrome. A waiting task-timer robot retains the project name inside its held sign.
- Saved receipts retain their frozen destination. During a named-project recording session, their confirmation no longer replaces the persistent robot.
- Camera-island recording stays in the bottom position so physical hardware cannot obscure the held board or its grip. Quiet mode and Reduce Motion retain the informational board. Transparent sign margins remain outside the mouse/drop destination; project routing itself still follows the selected project.

## Verification

All 11 selected native Release suites pass, including 31 new controller checks and 53 new native sign-render checks. The Release app is installed locally as 0.4.24 (79), with a backup of the previous bundle and verified strict signatures and executable hashes. Live accessibility confirms the persistent corner sign while capturing and the retained Paused sign; the original paused setting was restored. Native fixtures verify the fixed 10-point labels, grip placement, long names, expanded chrome and timer board.

[Verification and evidence](qa/project-recording-sign-2026-10-03/README.md) cover the installed snapshot. Nine unrelated source views changed afterward and were preserved; the complete 79-suite regression was not rerun. No public release or App Store submission has been made.
