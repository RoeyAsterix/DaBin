# DaBin privacy & your data

Updated 23 September 2026

## Your daily board stays on your Mac

DaBin saves the content you choose to paste, drop or type: text, links, files, tasks, comments and reminders. It also keeps the capture time, any source path or URL supplied with the content, and local preview information. These help you find your work again. Original files stay at their source; DaBin keeps its own copies.

DaBin has no account, cloud sync, ads, analytics or external AI service. The developer does not receive your captures, searches or usage. DaBin does not track you across apps or websites.

## You choose what to capture

The clipboard is read when you explicitly paste into DaBin. Hovering over the robot does not read it. DaBin reads your pointer position to reveal the robot at a screen corner; it does not record your screen or monitor what you type elsewhere.

Files are accessed through your paste or drop. DaBin does not scan your folders. Theme, window position and preview preferences are stored locally.

## Optional website previews

Fetch link previews is off by default. Turning it on contacts websites for saved links that need a preview, including earlier captures, and for new links. The requested URL and your IP address reach the website and any servers it uses for redirects, images or icons. The website may log these requests under its own privacy policy. Only enable previews for links you are comfortable contacting.

DaBin uses Apple's Link Presentation framework for these requests. It does not send your files, notes, comments or tasks to those websites. Preview titles and images are saved locally.

Turn Fetch link previews off in Settings to stop queued requests and cancel active preview requests. This cannot undo requests already sent and does not remove previews already saved. Opening a saved link launches your browser, whose settings and the website's privacy policy apply.

## Software updates

The direct GitHub build checks for updates only when you choose Check for Updates. That request contacts GitHub, which receives your IP address and ordinary connection information under GitHub's privacy policy. DaBin sends its current version; it does not send captures, searches, comments, reminders, file names or archive contents.

When you choose Download & install, DaBin downloads the published release package from GitHub into its sandbox. It verifies the package's HTTPS origin, exact size and SHA-256 checksum before opening the built-in installer. The installer asks before changing the application, verifies the app, backs up the previous installation and leaves the capture archive in place. DaBin does not check or download updates silently. Mac App Store builds receive updates through the App Store instead.

## Reminders

DaBin asks for notification permission when you first save a reminder. Notifications are scheduled locally through macOS with a generic message, without the capture's contents. You can turn off a reminder in its record and save, or change DaBin's notification permission in System Settings.

## Keeping and removing your data

Captures and saved previews stay on this Mac until you remove them. There is no automatic expiry or cloud copy. Marking a task Completed keeps its original record. Minimize only collapses a capture on the board; it keeps the saved content.

Choose Remove on a capture and confirm to remove its record, comments, reminder and DaBin's saved copies, including previews and recovery copies for that capture. This cannot be undone in DaBin. Source files in their original locations are kept. If DaBin cannot finish removing local copies, it shows a warning and retries when you open the app again.

To remove all captures, first turn Fetch link previews off and turn off and save any active reminders. Choose Show DaBin data folder below, then quit DaBin. In Finder, move that whole DaBin data folder to Trash. Empty Trash when you are ready to permanently remove it. Do not delete only the database or individual day folders while keeping the rest of the archive.

Removing this data folder removes DaBin's capture index, archive, copied originals, previews and recovery copies together. Original files elsewhere on your Mac, exports and backups are separate and are not removed. Theme and window preferences are stored separately and may remain. Removing the app alone may leave its local data on the Mac. Removal is ordinary file and database deletion; DaBin does not promise forensic secure erasure.

## Backups and security

DaBin uses the macOS app sandbox. Its local data is not separately encrypted by DaBin; your Mac's account access and disk protection apply. Backups you create, including system backups, can contain your captures. You control their retention and removal.

To keep a backup, quit DaBin before copying the complete data folder. The developer cannot recover data that exists only on your Mac or delete your own backups for you.
