# Full QA and reopen correction

DaBin ignored a normal macOS reopen event when AppKit still reported its floating
panel as visible. That state can describe an occluded, transparent, or off-display
panel, so reopening the app appeared to do nothing. `AppDelegate` now routes every
explicit reopen to `CornerController.openDaily()`. The lifecycle suite injects the
reopen action and verifies both AppKit visibility states.

## Final verification

- Optimized Release test matrix: **36/36 suites passed** with no source changes
  during the run. See `full-run-report.json`.
- Lifecycle regression: **54 checks**, including the visible-panel and hidden-panel
  reopen cases.
- Native visual QA: **62 production-view renders passed**, including the complete
  island/eating sequence, light and dark appearances, Reduce Motion, Weekly, Search,
  cards, previews, settings, compact 380 × 290 layouts, and animation cleanup. See
  `native-view-renders.json`.
- The standalone ARM64 Release build and the Xcode Release build both passed.
- All **26 source-level Store packaging checks** passed. A Store-distribution app
  still requires an Apple Distribution signature and App Store Connect validation.
- The corrected standalone build was installed to `~/Applications/DaBin.app`.
  Strict deep-signature verification passed after the metadata-clean installation,
  the installed and built source fingerprints matched, and the local archive was
  byte-identical before and after installation.
- A real macOS reopen event reused the running DaBin process and exposed the complete
  accessible Daily interface. The process remained responsive at normal CPU usage.

The local standalone build remains ad-hoc signed. Browser distribution still needs
Developer ID signing and notarization; Store distribution uses the separate Xcode
Store channel.
