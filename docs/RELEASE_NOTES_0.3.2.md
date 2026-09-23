# DaBin 0.3.2

DaBin 0.3.2 includes the new camera-island home and friendly robot personality from 0.3.1, plus a direct-update reliability fix.

## Camera-island home

Open **… → Settings → Your quiet corner** and choose **Below camera island**. On a compatible MacBook, moving the pointer to the real camera cutout reveals DaBin directly underneath it. Displays without camera-island geometry continue using their corners.

## A friendlier robot

The native purple robot now peeks in, follows the pointer, welcomes a drop, chews while saving and reacts to success, partial success or failure. It also blinks, glances and occasionally shrugs while waiting. macOS Reduce Motion keeps the expressions and removes the moving or repeated reactions.

## Reliable direct updater handoff

The embedded installer now opens as a fresh macOS application instance. This ensures the already verified update path and checksum reach the helper every time. If an updater error occurs, the alert also shows the specific reason.

Earlier helpers, including 0.3.0 and 0.3.1, cannot apply this one correction to themselves if macOS reuses the helper without its arguments. This Mac therefore receives 0.3.2 through the same signed helper with the verified package supplied directly. Once 0.3.2 is installed, later GitHub releases can again be pulled from **Settings → Software updates**.

Captures remain in the same private local archive. The package is ARM64 and locally signed for the owner's Mac; wider direct distribution still requires Developer ID signing and Apple notarization.
