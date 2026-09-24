# DaBin 0.3.14

DaBin now gives every primary action and content filter a small visual label without adding space to its compact header.

## What changed

- Added custom hover tooltips to Add, Search, Export, Notifications and Settings.
- Added the same treatment to All, Copy/paste text, Links, Files, Media and Tasks.
- Shows the short label after a **220 ms** hover delay and exposes the same cue when the icon receives keyboard focus.
- Dismisses the label when the control is activated and clears it after pointer and keyboard focus leave.
- Keeps complete accessibility names on every icon-only control.
- Preserves the existing **280 × 34-point** action and filter row geometry.

The exact source passed all **30 registered optimized Release suites**. The header suite passed **39 checks**, and **46 production-view renders** include first-action and last-filter tooltip coverage in light and dark appearance at the 380-point board width. The ARM64 build and verified update package are complete; public publication and the installed-app update are the remaining release steps.
