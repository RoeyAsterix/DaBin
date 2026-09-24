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

The exact source passed all **30 registered optimized Release suites**, including **46 compact-header checks**. **50 production-view renders** cover Daily and Weekly, light and dark appearances, 380-point narrow layout, Retina output and both new tooltip positions. A verified packaged build then passed a real pointer dwell, accessibility inspection and Daily → Weekly → Daily interaction. The local 33-file archive and preferences remained byte-identical. The ARM64 build and isolated update package also passed their signature, extraction, replacement, backup and hash checks.

Public publication and the installed-app update are the remaining release steps.
