# DaBin 0.4.10 (65) - clearer capture timestamps

The original capture date and time on the capture page use 16-point, medium-weight, high-contrast text (previously 11-point muted text). Clicking that date still opens the original capture day.

Daily, weekly, project, Explorer and batch cards place the original date and time before their category. Narrow cards stack the date above the time while keeping the category intact to their right; wider cards use one line. Hourly groups retain their date, hour range, action count and source application. Timestamps use the saved capture day and original recorded UTC offset; edits and later time-zone changes do not alter them.

This candidate also includes 0.4.9's click-to-open file previews. It is not a public release.

## Verification

Eight targeted Release suites passed without source changes during the run: `native/build/qa/runs/20261001T164321401556Z/report.json`. This is scoped coverage, not a new full-suite run. Coverage includes 129 timestamp formatting/layout/navigation checks, 110 preview-click interaction checks, 209 workspace layout checks, 202 header checks, 156 daily capture checks, 216 domain assertions, weekly window checks and 27 update configuration checks. The timestamp suite also produced 11 own-window fixture screenshots in `native/build/qa/capture-timestamp/`.

The final optimized ARM64 app and embedded updater were built and signature-verified in `native/build/DaBin.app`. The runtime inputs match the build receipt. Production rendering passed 52 release UI scenes (including narrow weekly and batch cards), 20 Explorer scenes and 24 fitted-preview scenes in light/dark modes. PDF snapshots verify surrounding layout; actual PDF page navigation is covered separately by the native interaction tests.

## Local deployment

The installed 0.4.8 app remains running and was unresponsive during the previous update attempt. The installed bundle and capture archive have not been replaced. Installation requires a safe exit or explicit permission to force-quit a potentially unsaved session.
