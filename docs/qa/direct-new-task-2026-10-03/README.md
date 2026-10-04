# Direct New Task button — 3 October 2026

The upper + control now opens the existing New Task screen directly. Its submenu was removed, and its tooltip/accessibility label is “New task.” The 28 × 32 target and existing header styling are retained. Opening this screen remains available during an import because it only navigates; the attachment import controls keep their own guards.

`BoardView.swift` uses `state.openNewTask()` so existing draft, destination, and return navigation behavior is preserved. The existing native header test now presses the actual + control and verifies direct New Task navigation and Back to the prior Daily view.

Verification passed in Release: 219 native header/accessibility/interaction checks and 131 task workflow checks. The test sources did not change during the run. The full suite was not run for this small UI change.

The local update was built in `/private/tmp/dabin-direct-new-task-20261003/native` from the previously verified installed production inputs plus this button change, avoiding installation of unfinished concurrent search work. The project source contains the same button update. `installed-build-receipt.json` records the exact built sources.

Installed and reopened `/Users/roeylibfeld/Applications/DaBin.app`, version 0.4.24 (79). Strict signature, executable hash, and source fingerprint verification passed. The previous app was backed up to `/Users/roeylibfeld/Applications/.DaBinBackups/20261003-164159-4ade6a74.app`.

The installed accessibility state showed + as a “New task” button rather than a menu button. Clicking it immediately showed the New task heading and Task text editor. No task was entered or saved; Auto Capture remained paused.
