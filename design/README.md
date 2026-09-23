# DaBin design prototype

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

Open [index.html](./index.html) in a browser to review the interactive macOS widget design. The persistent surface is a small **metallic purple robot bin**. Drag its dedicated handle to reposition it, then drop content onto its body or single-click it to paste. The robot briefly “digests” a successful capture. **Double-click the robot** to open the Daily board; `⌘O` is the keyboard route while the robot is focused. The board has date navigation, All / Links / Files / Media filters, card details, comments, reminders, and a compact-robot control.

The design is documented in [DESIGN_SPEC.md](./DESIGN_SPEC.md). Still previews show the [robot alone](./robot-preview.png), [robot with Daily board](./preview.png), [digest reaction](./digest-preview.png), [compact form](./compact-preview.png), [dark appearance](./dark-preview.png), and [narrow layout](./narrow-preview.png).

This is a local design prototype. Its sample cards are fictional, and newly dropped or pasted items remain only in the open browser session. The digest animation is feedback for demo capture, not evidence that file bytes were stored. Link metadata fetching, durable file storage, native floating-window behavior, and system notifications belong to the subsequent macOS implementation.
