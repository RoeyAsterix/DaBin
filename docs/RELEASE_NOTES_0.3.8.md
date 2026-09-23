# DaBin 0.3.8

DaBin 0.3.8 adds complete-day export and makes the Daily and Weekly header substantially more compact.

## Export Day

A new purple **Export Day** icon sits between Search and Notifications. It opens a small action popover with two choices:

- **Copy Day** copies the selected date as plain text.
- **Export Text File** saves the same UTF-8 text as `DaBin-YYYY-MM-DD.txt` in a location you choose.

The export always includes the complete selected calendar date, even when a content filter is active. Actions are ordered from earliest to latest and include their date, time, type, available source application and available text. Multi-item pastes and drops remain one action with every item included. Image-only actions include their caption or OCR text when stored, or a clear screenshot or image placeholder.

Today includes actions recorded up to the moment you export; earlier dates include their complete stored day. An empty date disables both choices and says **Nothing to export.** Copy success briefly shows a checkmark and **Day copied.** Cancelling the save panel leaves the board unchanged, while copy and save errors are reported in place.

The popover supports normal keyboard navigation, visible focus, Command-C and Command-S shortcuts, Escape dismissal, outside-click dismissal, help text and VoiceOver labels.

## Compact header

Daily and Weekly now use three closely spaced rows:

1. The DaBin logo, date navigation, selected date, Daily/Weekly control and neutral close button.
2. Add, Search, Export Day, Notifications and Settings.
3. The existing All, Links, Files, Media and Tasks filters.

The action and filter rows share one center axis and the same colored icon language. Oversized spacers were removed, so the board keeps more room for captures while remaining usable at its 380-point compact width. Existing navigation, filters and actions keep their behavior.

## Update

From DaBin 0.3.7, open **Settings → Software updates**, choose **Check for updates**, then **Download & install**. DaBin verifies the release size and SHA-256 checksum before its installer asks to replace the app. Your local capture archive stays in place.
