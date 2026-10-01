# DaBin 0.4.7 (62) - local candidate

## Projects lead

- The primary workspace destination is now labeled **Projects**, and project identity appears above capture content so ownership is easier to scan.
- Each project can use one of eight accessible colors. Choose a color while creating a project or change it later from the project menu.
- When a project is open, its capture and resource cards receive a restrained frame in that project's color.

## Project-aware Auto Capture

- Clipboard and screenshot Auto Capture saves go directly to the project selected when the event begins. With no selected project, they remain unfiled.
- After each project capture, the robot holds and waves a small color-matched sign with the project name. Rapid saves retain their own destinations, and Reduce Motion keeps the sign static.
- The board's Auto Capture status names the current destination before recording begins.

## Cleaner controls and compatible storage

- Redundant, duplicate and inert visible actions have been removed from the Inbox, cards, detail view and Explorer. Useful contextual, keyboard and accessibility paths remain available.
- Existing archives remain readable. Project colors and automatic-capture destinations use additive optional metadata, with a default project color for older workspaces.

## Verification and distribution

Local verification is complete on this Mac: all 59 registered Release suites passed, the production UI render sets passed visual review, and build 62 passed guarded upgrade installation, strict signature, architecture and executable-hash checks. It remains a local candidate—not a public release, notarized installer or Apple-approved build. The public GitHub release remains 0.3.18 until the remaining distribution gates are complete.
