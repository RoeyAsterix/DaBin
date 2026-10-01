# DaBin 0.4.18 (73): two-second UI messages

Brief notification banners and robot message popovers now disappear after at most two seconds. The same presentation policy covers reminder feedback, successful detail/scratchpad saves, clipboard cleanup confirmations, and trail/source/export operation messages. Existing shorter copy confirmations stay shorter.

Identical messages get a fresh deadline. Old callbacks cannot hide a newer result, expired banners leave no reserved height, and export success cannot later close a newer failure. Dismissal and expiry hide presentation only: saved captures, error diagnostics and reminder state are retained.

Unsaved-form errors, recovery actions, Undo, in-progress/state indicators and the task timer robot remain available. The task alarm still returns home only when clicked. System notification timing is controlled by macOS.

All **20 selected Release QA suites** passed against frozen inputs, including **54 new notification checks**. Exact fake-clock boundaries, canceled/repeated receipts, actual offscreen Board/Detail/Settings accessibility removal, export retry races, clipboard cleanup feedback and unchanged fictional capture/file data passed. Actual 2× native renders were reviewed before/after expiry. This is targeted verification, not a full distribution review.

The local app is installed and running, with strict signatures and executable hashes matching the build receipt. Settings confirms **0.4.18 (73)**. Tooltips remain enabled, Auto Capture remains paused and Explorer is open. The previous app was quit normally and backed up; the installer did not modify the capture archive. No personal capture or timer was created for testing. The personal archive was not independently byte-inventoried.

[Local installation evidence and limitations](qa/local-install-0.4.18-2026-10-02/verification.json). This candidate is not published; public downloads still contain 0.3.18.
