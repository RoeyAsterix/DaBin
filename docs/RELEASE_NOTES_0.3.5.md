# DaBin 0.3.5

DaBin 0.3.5 adds an optional Auto Capture mode for people who want a fuller record of what they worked with during the day.

## Auto Capture starts only when you ask

Open **DaBin → Settings → Capture** and turn on **Auto Capture**. It is off by default. Before it starts, DaBin explains that captured content stays in the local DaBin archive and asks you to choose the folder where macOS saves screenshots.

DaBin then watches future clipboard changes and new image files written to that selected folder. Use a dedicated screenshot folder because every new image there is treated as a screenshot. It does not import anything already on the clipboard or already in the folder. The app records the time, content type and best-effort source application when one is available.

Use **Pause Auto Capture** in DaBin or the app menu to stop monitoring immediately. Turning the setting off does the same. Existing captures remain. DaBin and common password managers are excluded by default, and you can edit the exclusion list in Settings.

## A calmer Daily feed

The first three automatic actions in a clock hour appear as normal cards. The fourth turns that hour into one summary, such as **14:00–14:59 · 4 actions**. Its count updates as new actions arrive. Click the summary to expand it in place, then use the minus button to collapse it without losing your feed position.

After a complete automatic action saves successfully, the DaBin robot briefly appears on the primary display. A burst reuses one robot and increases its count. The panel does not take focus or clicks, stays inside the screen's safe area, is excluded from screen capture, and follows Reduce Motion.

## Privacy and platform scope

Automatic captures use the same local archive as manual drag and paste. Automatically captured links never fetch website previews. A normalized image fingerprint normally prevents one screenshot from becoming both a screenshot action and a clipboard action.

macOS does not provide ordinary sandboxed apps with a public event for every screenshot. DaBin monitors the screenshot folder you explicitly choose; images saved elsewhere are outside that folder monitor. Source-application attribution is also best effort. Pause or turn off Auto Capture before handling content you do not want monitored.

## Update

From DaBin 0.3.4, open **Settings → Software updates**, choose **Check for updates**, then **Download & install**. DaBin verifies the release size and SHA-256 checksum before its installer asks to replace the app. Your capture archive remains in place.

The downloadable update ZIP also includes the app, updater, release manifest, instructions and the refreshed one-page PDF guide.
