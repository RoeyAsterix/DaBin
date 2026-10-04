DaBin native guided demo assets — 2026-10-04

25 actual native UI states, 2360 × 1404 PNG. Rendered from the frozen
0.4.31 (86) production QA module with a fictional isolated local archive.
No live app, clipboard, network, notifications or capture monitoring used.

Manifest: native-v2-renders.json
Provenance and limitations: native-v2-provenance.json
Visual contact sheet: DABIN__QA__V2_NATIVE_STATES.png

Robot: DABIN__ROBOT__IDLE/HUNGRY/DELIGHTED/PUZZLED/CURIOUS_LEFT/
CURIOUS_RIGHT/BLINK.png. Same 902 × 728 transparent canvas.
Mouth: DABIN__MOUTH__IDLE/HUNGRY/DELIGHTED.png. Same 902 × 728
transparent canvas; place over the robot at an identical origin to swap
exact native mouth pixels.
Focus alarm: DABIN__ROBOT__FOCUS_ALARM.png, actual native timer-end example.

Reproduce: python3 ReproduceNativeAssets.py, then run
FinalizeNativeAssets.py with a Python runtime containing Pillow.
Frozen module hashes are enforced. This does not rebuild or modify app source.
Exclude .build from the delivery ZIP.

Settings version is the fixture executable's 0.0.0 (0): crop the actual
Automatic capture section below its version panel. Do not redraw UI.
Backup route is verified native More → Back up archive…, but no system menu
or file dialog was opened. Focus and reminder demonstrations do not schedule
OS notifications. Frame transitions in the video are editorial animation,
not a live recording of interactions.
