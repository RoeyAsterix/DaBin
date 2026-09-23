# DaBin — micro-widget design prototype

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

Open [index.html](./index.html) to review the local browser prototype. It began as the Open Design project `dabin-purple-robot-redesign` and is being refined around a much smaller resting presence. The earlier concept remains in `../design/` for comparison.

The resting interface is an **edge-docked, 52 × 64 CSS pixel purple metal robot bin**. Its shell is the drop target. There is no persistent plus button, badge, count, or compact toggle. Click once to open a small paste composer; double-click to open Daily.

Daily is an on-demand popover targeting **about 336 CSS pixels wide and no more than 410 pixels tall**. It uses one compact header row for date navigation, search, reminders, and close, followed by a filter row and a scrolling list. There is no side menu or simulated desktop background. Each capture has a 44-pixel preview plus visible **Comment** and **Reminder** actions.

Search shows only dates with matching captures. Each match appears with the immediately preceding and following capture from the same day, in capture order; overlapping context is shown once.

See the [design notes](./DESIGN_NOTES.md) and [preview gallery](./previews/index.html). Preview images and the [local QA record](./LOCAL_QA.md) should be reviewed against the current implementation, as the design is still being revised.

This is a browser prototype, not a native macOS app. Captures last only for the browser session. Native floating-window behavior, durable file storage, live link metadata, and OS notifications remain implementation work.
