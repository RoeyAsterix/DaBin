# DaBin 0.3.16

DaBin 0.3.16 gives the Daily and Weekly switch the same clean purple icon design as the rest of the header.

## What changed

- Replaces the text segment with two matched calendar icons: **1** for Daily and **7** for Weekly.
- Uses the same purple symbol color, circular selected and hover states, press animation and keyboard focus ring as the action and filter icons.
- Adds the same small delayed **Daily** and **Weekly** hover labels.
- Keeps full **Daily view** and **Weekly view** accessibility names, selected state and keyboard activation.
- Reduces the control from 92 to 80 points so the compact Weekly header has more room.
- Preserves date navigation, view switching, filters, scroll position, drafts and the independent close control.

## Verification

The exact source passed all **30 registered optimized Release suites**, including **46 compact-header checks**. **50 production-view renders** cover Daily and Weekly, light and dark appearances, 380-point narrow layout, Retina output and both new tooltip positions. A verified packaged build then passed a real pointer dwell, accessibility inspection and Daily → Weekly → Daily interaction. The ARM64 build and update package also passed their signature, extraction, replacement, backup and hash checks.

The public release assets were downloaded without authentication and matched their local bytes. DaBin then updated itself from **0.3.15 (40)** to **0.3.16 (41)** through Settings. The installed app repeated the pointer, accessibility and mode-switch checks, reported that it was current, and retained all 33 archive files, preferences and the Desktop link unchanged. The updater preserved an exact verified backup of 0.3.15.
