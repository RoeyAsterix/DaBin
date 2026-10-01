# DaBin 0.4.12 (67) - restored tooltips

Hover labels are visible again across the redesigned board. They follow each control's actual position rather than the removed header's old coordinates, wrap long descriptions and flip above bottom-edge controls. The overlay does not change content layout, accept clicks, open an extra window or run a polling timer.

Use **Settings → Appearance → Show tooltips** to turn them off or back on. The existing preference is now applied consistently to the board, popovers, sheets, native drag handles, island robot and menu-bar status button. New profiles default to enabled; existing saved choices remain unchanged. Turning help off cancels pending and visible labels immediately, and the choice survives relaunch. Control names, accessibility help and keyboard actions remain independent of visual tooltips.

This candidate also includes the pending robot consistency, preview-click and capture timestamp updates.

## Verification and local deployment

The optimized ARM64 Release candidate has been built with the embedded updater and strict signature verification on a clean copy. Its build receipt matches every current runtime input. All 15 selected regression suites passed against these sources: [final QA report](../native/build/qa/runs/20261001T181717604874Z/report.json).

Tooltip-specific coverage includes 108 controller/layout checks, 30 native preference/lifecycle checks and 136 native presentation checks. Production board views were rendered at compact and expanded widths in light and dark appearance. The actual Settings switch was revealed and clicked in its own fixture window, verifying both immediate behavior and saved off/on choices. A visible bubble covering another native button still delivered exactly one callback per click. Accessibility names and help remain available with tooltips disabled. See the [presentation evidence](../native/build/qa/tooltips/tooltip-presentation-report.json), [restored hover label](../native/build/qa/tooltips/board-380-light-board-settings-tooltip@2x.png) and [Settings switch](../native/build/qa/tooltips/board-380-light-settings-tooltips-enabled@2x.png).

These checks use fictional captures, isolated preferences and own-process windows, not the personal archive or installed app. Actual desktop pointer dwell and installed-app live verification remain pending a safe exit from the unresponsive older 0.4.8 (63) process or explicit permission to force-quit it; unsaved edits could otherwise be lost. No installation has occurred. This candidate is not a public release.
