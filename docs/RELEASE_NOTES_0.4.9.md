# DaBin 0.4.9 (64) - click previews to open files

Click the file preview on a capture page or in Explorer's inspector to open its saved original in the default macOS application. The preview is also an accessible button for keyboard and assistive-technology users.

Images and document thumbnails retain their fitted layout and background image cache. PDFs display a fitted page without inactive inline page controls; videos display their saved thumbnail and play symbol. Full document navigation and video playback take place in the file's normal application.

Opening uses the existing validated archive path and missing-file feedback. A thumbnail with no valid original attachment does not offer a dead file-opening button. Captures, project colors and Auto Capture settings are unchanged.

## Verification and local deployment

The five targeted Release suites passed without source changes during the run: `native/build/qa/runs/20261001T161458267049Z/report.json`. This is scoped coverage, not a new full-suite run. It includes 110 native preview interaction checks (mouse clicks, accessibility activation, all six file types, passive PDF navigation, invalid attachments and missing-file feedback), 209 workspace layout checks, 202 header interaction checks, 15 background-preview checks and 27 update-configuration checks.

The optimized ARM64 app and updater were built and signature-verified in `native/build/DaBin.app`. Local installation remains pending: the running 0.4.8 process did not respond to UI controls. A three-second process sample showed approximately 11 GB of physical memory and continuous SwiftUI layout work. The installed app and archive were not replaced; permission is required before force-quitting a potentially unsaved session. Sample: `/private/tmp/DaBin-preview-click-before-install.sample.txt`.

This is not a public release.
