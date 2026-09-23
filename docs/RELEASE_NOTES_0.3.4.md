# DaBin 0.3.4

DaBin 0.3.4 brings Daily and Weekly together in one compact control and repairs the direct updater handoff found during live installation QA. It supersedes 0.3.3.

## Daily and Weekly

- The old **Today** and **This Week** actions are now one compact **Daily / Weekly** segmented control.
- **Weekly** opens the seven days ending on the date already selected in Daily.
- Switching back to **Daily** keeps that date, the active type filter, Daily scroll position and unfinished edits.
- The centered date shortcut, day headings, Back navigation, directional panel transition and Reduce Motion behavior continue to work.

## Reliable sandboxed updates

The 0.3.3 installer launch relied on application arguments that macOS does not deliver from a sandboxed caller. This could produce a missing-file message before the installer changed anything.

DaBin now passes the verified download through a private, one-use update document. The installer validates and consumes that document, independently checks the package and app, asks before replacement, and keeps its existing backup and rollback protections.

The updater does not read, move or delete the local capture archive. Captures, comments, reminders, tasks, settings and saved files remain where they are.

## Update

Open **DaBin → Settings → Software updates**, choose **Check for updates**, then **Download & install**.

If DaBin 0.3.3 reports that `DaBin.app` is missing, download the 0.3.4 release ZIP, extract it and open **DaBin Update.app**. The downloadable package also includes the app, release manifest, instructions and one-page PDF guide.
