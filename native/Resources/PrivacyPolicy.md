# DaBin privacy & your data

Updated 24 September 2026

## Your daily board stays on your Mac

DaBin saves the content you choose to paste, drop or type: text, links, files, tasks, comments and reminders. If you separately enable Auto Capture, it can also save later clipboard changes and new image files from a folder you authorize as your screenshot location. DaBin keeps capture time, any available source path or URL, best-effort source-application information for automatic captures, and local preview information. These help you find your work again. Original files stay at their source; DaBin keeps its own copies.

DaBin has no account, cloud sync, ads, analytics or external AI service. The developer does not receive your captures, searches or usage. DaBin does not track you across apps or websites.

## Local text recognition and search

DaBin uses Apple frameworks on this Mac to recognize text in saved images, screenshots, PDFs and supported text documents. It reads DaBin's own saved copy after the capture succeeds. Recognition does not record the live screen, contact a website, use an external AI service or upload the file or recognized text. It does not require Screen Recording permission.

Recognized text is stored with the capture in the same local archive and is used by Search and text exports. A PDF with an existing text layer is read directly; image-only pages are recognized locally. DaBin limits the amount of very large documents it processes and reports a partial index when that limit applies. You can inspect recognized text in capture details and rebuild the local index from Settings. Removing the capture also removes its recognized text.

## Manual capture

With Auto Capture off, the clipboard is read only when you explicitly paste into DaBin. Hovering over the robot does not read it. DaBin reads your pointer position to reveal the robot at a screen corner or, if you select it on a compatible Mac, below the built-in camera island. Camera-island placement uses ordinary macOS screen safe-area geometry; it does not use the camera, record your screen or monitor what you type elsewhere.

Manual file captures are accessed through your paste or drop. Outside the screenshot location you separately authorize for Auto Capture, DaBin does not scan your folders. Theme, window position, robot-home, preview and Auto Capture preferences are stored locally.

## Optional Auto Capture

Auto Capture is **off by default** and begins only after you enable it. When clipboard monitoring starts, DaBin records the clipboard's current change count as a baseline. It does not import what was already on the clipboard; only changes made after enabling or resuming monitoring are considered. Choosing Pause or turning Auto Capture off stops clipboard polling and screenshot-folder monitoring immediately. Content already saved remains in your archive until you remove it.

To watch screenshots, DaBin asks you to choose their save folder with the macOS folder picker. It stores a security-scoped bookmark locally so it can regain access to that chosen location while monitoring is enabled. Existing images form a baseline and are not imported when monitoring starts. New regular image files added there are treated as screenshot captures, even if another app created them for a different purpose, so DaBin recommends a dedicated screenshot folder. DaBin does not scan unrelated folders. Revoking the folder grant stops Auto Capture until you choose a folder again.

macOS does not provide apps with a public notification for every system screenshot. Folder monitoring therefore covers screenshots written to the location you chose. A screenshot whose destination is the clipboard can be detected as a later clipboard change. Screenshots saved elsewhere are outside the chosen folder monitor. DaBin reads the resulting file or clipboard representation; it does not record the live screen and does not request Screen Recording access for this feature.

DaBin saves a source application when macOS makes one reasonably identifiable at capture time. This is best-effort information: focus can change, and the app can be unknown or imprecise. It is not proof of where content originated. DaBin itself and common password managers are excluded by default. Because source detection has limits, these exclusions are an additional safeguard rather than a guarantee. Pause or turn off Auto Capture before handling content you do not want it to observe.

For a single image seen through both the screenshot folder and clipboard within a short interval, DaBin compares a normalized image fingerprint and suppresses the second channel's copy. Copying the same image again through one channel remains a new action. Automatic captures use the same local archive as manual captures. Their contents are not uploaded. Automatically captured links never fetch website previews, even if Fetch link previews is enabled for manually saved links.

Successful automatic saves produce a brief, noninteractive robot confirmation. Four or more successful automatic actions in the same capture hour appear as an expandable hourly group in Daily. The popup is shown after the triggering item has been saved and is excluded from screen capture while it is visible.

## Optional website previews

Fetch link previews is off by default. Turning it on contacts websites for eligible manually saved links that need a preview, including earlier manual captures, and for new manual links. Automatically captured links are never eligible for these requests. For an eligible link, the requested URL and your IP address reach the website and any servers it uses for redirects, images or icons. The website may log these requests under its own privacy policy. Only enable previews for links you are comfortable contacting.

DaBin uses Apple's Link Presentation framework for these requests. It does not send your files, notes, comments or tasks to those websites. Preview titles and images are saved locally.

Turn Fetch link previews off in Settings to stop queued requests and cancel active preview requests. This cannot undo requests already sent and does not remove previews already saved. Opening a saved link launches your browser, whose settings and the website's privacy policy apply.

## Software updates

The direct GitHub build checks for updates only when you choose Check for Updates. That request contacts GitHub, which receives your IP address and ordinary connection information under GitHub's privacy policy. DaBin sends its current version; it does not send captures, searches, comments, reminders, file names or archive contents.

When you choose Download & install, DaBin downloads the published release package from GitHub into its sandbox. It verifies the package's HTTPS origin, exact size and SHA-256 checksum before opening the built-in installer. The installer asks before changing the application, verifies the app, backs up the previous installation and leaves the capture archive in place. DaBin does not check or download updates silently. Mac App Store builds receive updates through the App Store instead.

## Reminders

DaBin asks for notification permission when you first save a reminder. Notifications are scheduled locally through macOS with a generic message, without the capture's contents. You can turn off a reminder in its record and save, or change DaBin's notification permission in System Settings.

## Keeping and removing your data

Manual and automatic captures and saved previews stay on this Mac until you remove them. There is no automatic expiry or cloud copy. Pausing or disabling Auto Capture stops new monitoring but does not delete earlier captures. Marking a task Completed keeps its original record. Minimize only collapses a capture on the board; it keeps the saved content.

Choose Remove on a capture and confirm to remove its record, comments, reminder and DaBin's saved copies, including previews and recovery copies for that capture. This cannot be undone in DaBin. Source files in their original locations are kept. If DaBin cannot finish removing local copies, it shows a warning and retries when you open the app again.

To remove all captures, first turn Auto Capture and Fetch link previews off, then turn off and save any active reminders. Choose Show DaBin data folder below, then quit DaBin. In Finder, move that whole DaBin data folder to Trash. Empty Trash when you are ready to permanently remove it. Do not delete only the database or individual day folders while keeping the rest of the archive.

Removing this data folder removes DaBin's capture index, archive, copied originals, previews and recovery copies together. Original files elsewhere on your Mac, exports and backups are separate and are not removed. Theme, window, robot-home and Auto Capture preferences, including the selected-folder bookmark, are stored separately and may remain. Removing the app alone may leave its local data on the Mac. Removal is ordinary file and database deletion; DaBin does not promise forensic secure erasure.

## Backups and security

DaBin uses the macOS app sandbox. Its local data is not separately encrypted by DaBin; your Mac's account access and disk protection apply. Backups you create, including system backups, can contain your captures. You control their retention and removal.

To keep a backup, quit DaBin before copying the complete data folder. The developer cannot recover data that exists only on your Mac or delete your own backups for you.
