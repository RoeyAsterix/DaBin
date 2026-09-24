# DaBin 0.3.15

DaBin 0.3.15 is a focused tooltip hotfix for the Settings gear in the compact header.

## What changed

- Moves Settings hover tracking from the gear's inner label to the outer native Menu that owns pointer hit testing.
- Restores the small **Settings** visual label while retaining **Settings and options** as the complete accessibility name.
- Keeps the existing 220 ms delay, keyboard-focus cue, accessible name and click behavior.
- Leaves every other action and filter tooltip unchanged.
- Preserves the two **280 × 34-point** icon rows and all existing Settings menu actions.

DaBin 0.3.14 was published and installed successfully through the app's verified updater. Live pointer QA after installation found that SwiftUI's native Menu intercepted hover events before they reached its inner gear label; the other ten tooltips worked as released.

## Verification

The exact source passed all **30 registered optimized Release suites** and **46 production-view renders**. The exact ARM64 Release build then passed a real pointer dwell over Settings: the tooltip appeared, kept its full accessibility name, remained hidden from the accessibility tree itself, and the native Settings menu opened afterward. The verified update package passed isolated installation, replacement, backup, signature, extraction and hash checks. Public publication and the installed-app update are the remaining release steps.
