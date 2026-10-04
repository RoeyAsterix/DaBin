# Task priority color tags — 3 October 2026

Task priority choices now use labeled pills: green Low, amber Medium, and red High. No priority is a neutral choice that removes the tag from a task. Selection uses a stronger outline, and readable text/accessibility labels accompany every color.

The shared observed tag appears on Daily/Inbox/Today task cards, Weekly cards, expanded and compact grouped items, Projects Explorer and its inspector, Clipboard/Shelf cards, and task details. It stays visible on minimized tasks. The duplicate priority icon in Today was removed. Existing priority values, persistence, and task sorting remain compatible.

The concurrent date-search result card also has the shared tag insertion in project source. That unfinished search feature was kept out of this installed build; the existing installed search cards use CaptureRow and receive the tag through it.

## Verification

Six Release suites passed with no source changes during the run: TaskPriorityTagTests (200 checks), TaskStateTests (131), TaskPlanningTests (39), HeaderInteractionTests (219), WorkspaceWindowTests (214), and WeeklyWindowTests. The native priority test presses the real choices and Save changes button, verifies a retained card updates without remounting, reopens the isolated archive, checks preserved task text/schedule/checklist, and samples actual green/amber/red badge pixels.

Twelve fictional native render PNGs are saved in `renders/`, including 380/760 layouts in light and dark themes. The compact task-card, Explorer and editor renders were visually inspected. The full suite and macOS 14 runtime were not run for this change.

The installation candidate was built from the previously verified local direct + update plus the eight priority presentation files. All production sources in the installed receipt match the passing QA inventory. The priority production files also match the project source; see `priority-source-attestation.json`. No personal task was entered or saved during verification.

## Local installation

Installed and reopened `/Users/roeylibfeld/Applications/DaBin.app`, version 0.4.24 (79). Strict code signature, executable hash, and source fingerprint verification passed. The previous app was preserved at `/Users/roeylibfeld/Applications/.DaBinBackups/20261003-165928-31bea044.app`.

The installed New Task screen exposes No priority, Low priority, Medium priority, and High priority as separate labeled buttons. Auto Capture remained paused. `installation.json`, `installed-build-receipt.json`, `report.json`, and adjacent logs record the verification.
