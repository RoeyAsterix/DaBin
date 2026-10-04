# Local file locations — 3 October 2026

The Projects Explorer and Shelf **Files** actions now open the selected project's physical folder in Finder. **Add files** remains a separate import action. All projects opens the complete library root; Unfiled opens its own physical folder. The Explorer footer uses the same folder resolver.

Settings **Open local archive** now opens the full local library, including Projects, Unfiled, and the older Archive receipt folders. A capture's **Show saved folder** opens the parent directory of its current, validated saved original, including after a project move. Notes and tasks without an original open their effective project's dated directory containing the readable daily record. Missing saved originals produce an error instead of opening an unrelated source or metadata folder.

The historical source path and receipt archive maintenance APIs remain intact. Folder opening does not trigger capture synchronization or file moves. Shelf controls retain distinct accessibility names through an explicit containing accessibility element.

## Verification

Four Release suites passed with no source changes during the run: LocalFileLocationTests (44 checks), ProjectFileArchiveTests (56), CaptureRemovalTests (76), and WorkspaceWindowTests (214). The new integration suite presses the actual Explorer, Shelf, Settings, and capture-detail buttons with a read-only opener spy. It also covers project movement, effective task-parent projects, All projects and Unfiled, preserved original bytes, stale/deleted records, missing files, and opener failure feedback. Fixtures use disposable fictional data and offscreen native windows. The complete suite and a macOS 14 runtime were not run.

Two earlier runs passed the three existing suites but found that the Shelf container label replaced its child button names. Their reports and logs are preserved under `prior-runs/`. The final run passes after the containing-element correction.

All production sources in the installed build receipt match the passing QA inventory. The candidate extends the previously verified priority-tag build. Folder changes in the shared AppState and Explorer files were transplanted into that stable baseline, preserving unfinished date-search work in the project source. `folder-source-attestation.json` records the source comparison.

## Local installation and Finder verification

Installed and reopened `/Users/roeylibfeld/Applications/DaBin.app`, version 0.4.24 (79). Strict code signature, executable hash, and source fingerprint match the verified candidate. The previous app is preserved at `/Users/roeylibfeld/Applications/.DaBinBackups/20261003-172512-29b14953.app`.

The installed Projects Explorer **Files** button opened Finder at the selected Kari project folder, `/Users/roeylibfeld/Library/Containers/com.dabin.mac/Data/Library/Application Support/DaBin/Projects/Kari — 1262ca620719/`, showing its 2026 directory. Settings **Open local archive** opened Finder at `/Users/roeylibfeld/Library/Containers/com.dabin.mac/Data/Library/Application Support/DaBin/`, showing Projects, Unfiled, and Archive. No personal file was imported, edited, or deleted during these checks. Auto Capture remained paused, and DaBin was left on Projects Explorer with both Files and Add files available.

`installation.json`, `installed-build-receipt.json`, `report.json`, `live-finder-verification.json`, and adjacent logs record the result.
