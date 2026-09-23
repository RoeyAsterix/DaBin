# DaBin 0.3.1 QA evidence

- `full-run/report.json` is the machine-readable Release run for all 23 registered suites. Adjacent execution logs preserve every suite outcome.
- `media-integration-v0.3.1.log` covers synthetic PDF, RTF and H.264 previews and fitted PDF geometry.
- `release-ui-renders.json` inventories 28 production board renders and 10 direct 2x transient-robot renders. The generated PNG set remains outside Git history.
- `robot-personality-renders.json` records distinct idle, curious, hungry, digesting, delighted, partial-success and puzzled poses, live digest movement, Reduce Motion stability and hidden-state cleanup.
- `live-camera-island-v0.3.1.json` and `live-robot-below-camera-island.png` record the real two-display camera-island check on this Mac.
- `app-store-preflight-static-v0.3.1.log` records 20 passing source/package checks.
- `app-store-preflight-release-v0.3.1.log` records the two remaining release-environment blockers: Apple Developer Team ID and full Xcode.
- `build-receipt-v0.3.1.json` and `update-manifest-v0.3.1.json` identify the exact optimized build and update ZIP.
- `release-publication.json` is added after publication to record unauthenticated release, manifest, asset, installation and live-update checks.

All automated fixtures are synthetic and isolated. The live camera-island check moved only the pointer and the local Robot home preference; it did not capture, paste, drop, edit, notify or contact a website.
