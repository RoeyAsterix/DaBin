# DaBin 0.4.13 (68) - capture-trail cleanup

Removed the manual add-paste plus button from capture trails across cards and capture pages. The Content trail popover no longer offers Record a paste, the destination picker or a custom destination field. Existing source information and stored paste receipts are preserved. Legacy manually recorded receipts retain their evidence labels and removal action for correcting old entries. Opening or copying content does not create a paste receipt.

This candidate includes the tooltip, robot consistency, preview-click and capture timestamp improvements.

## Verification and local deployment

The optimized ARM64 Release build is complete with the embedded updater and strict signature verification on a clean copy. The build receipt matches all current runtime inputs. All 16 selected regression suites passed: [QA report](../native/build/qa/runs/20261001T182718814017Z/report.json).

The 76 native redesign interaction checks cover absence of manual-add controls on ordinary/task cards and the history popover, preserved source and evidence labels, complete persisted receipts unchanged by opening/closing history, legacy manual receipt correction, unchanged confirmed receipts and exactly one normal Copy action without fabricated paste history. The 66 provenance checks continue to cover legacy metadata, persistence, rollback, restart, backup and exports. Existing tooltip, file-preview, timestamp, robot, header, window and lifecycle suites also pass. Tests use isolated preferences, fictional captures and own-process windows; they do not access the personal archive or installed app. See the [cleaned capture card](../native/build/qa/redesign-interactions/capture-before-conversion-380.png).

DaBin 0.4.13 (68) is installed and running at `/Users/roeylibfeld/Applications/DaBin.app`. With explicit user permission, the exact older DaBin process was force-quit before the guarded installer ran. The previous bundle is preserved at `/Users/roeylibfeld/Applications/.DaBinBackups/20261001-213248-fe600095.app`. The installer did not modify the archive. Installed main/helper executable hashes match the tested build; strict installed-bundle signature verification passes. The running app's Settings shows 0.4.13 (68), its Show tooltips preference is present, the visible capture cards have no add-paste button, and Settings → Back navigation responds. See the [local installation verification](qa/local-install-0.4.13-2026-10-01/verification.json).

No public release has occurred. The separate two-second-message request still needs identification of the intended message type; no tooltip or status expiry timing was changed in this candidate. This verification did not toggle preferences, edit or delete captures, resume Auto Capture, open saved originals or upload personal data. Full desktop pointer-dwell testing remains separate from the isolated tooltip fixture checks.
