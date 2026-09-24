# DaBin 0.3.17

DaBin 0.3.17 adds a visible way to quit the application completely and provides clear GitHub downloads for both updating and direct installation.

## What changed

- Adds **Settings → Application → Quit DaBin** with a power icon and plain explanation of what stops and what stays saved.
- Uses the standard macOS quit path, including DaBin’s checks for a removal in progress, content still being received, and unsaved task, comment, or reminder edits.
- Stops Auto Capture, clipboard polling, screenshot-folder monitoring, corner detection, previews, update work, observers, and all DaBin windows when quitting completes.
- Keeps the local archive, saved reminders, settings, and existing captures ready for the next launch.
- Publishes a one-click installer/update ZIP and a separate Apple Silicon direct-install ZIP. Both use `~/Applications/DaBin.app`, so later in-app updates replace the correct copy.

## Install or update

- **Update or one-click install:** download `DaBin-0.3.17-Update.zip`, open **DaBin Update.app**, then choose **Install** or **Update**.
- **Manual direct install:** download `DaBin-0.3.17-AppleSilicon.zip`, move **DaBin.app** to `~/Applications`, and open it.
- **In-app update:** in DaBin 0.3.16, open **Settings → Software updates**, check for updates, then choose **Download & install**.

Both packages are Apple Silicon only and require macOS 14 or later. They are locally ad-hoc signed for the owner’s Mac. General distribution to other Macs still requires Developer ID signing and Apple notarization.

## Verification

Release verification covers the full optimized test suite, Settings renders, ARM64 build identity, strict signatures, both ZIP round trips, isolated fresh install and replacement, public GitHub bytes, live update, direct-package launch, and a process-level check that **Quit DaBin** leaves no DaBin process running.
