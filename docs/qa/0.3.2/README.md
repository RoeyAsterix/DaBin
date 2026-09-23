# DaBin 0.3.2 release evidence

This directory records the final source, functional, visual, media, package and Store-readiness checks for DaBin 0.3.2 (27).

## Results

- **23/23** registered optimized suites passed, covering **1,917 checks**.
- Separate synthetic PDF, RTF and H.264 integration passed **39/39**, for **1,956 checks** in the release cycle.
- **28** production board renders and **10** direct native robot renders passed.
- The digest samples changed **45,620 raster bytes**; Reduce Motion and hidden cleanup changed zero bytes during their stability intervals.
- Static App Store packaging passed **20/20**. Release preflight is blocked only by the missing Apple Developer Team ID and full Xcode.
- The ARM64 Release build is 0.3.2 (27), source fingerprint `9cfa700e92720b2beda2c67e972c625f4ee5bb2d14ac01bca5ede19f4ea4c1e3`, executable SHA-256 `f95a3805ea5bf28f63afb529571a09546ce855e5ae1fa2b7ea78e19f87bfa00f`.
- The verified update ZIP is 2,940,064 bytes with SHA-256 `6ced075743d2af5497d94711071d34fed85b3fc6a36bc7f7c9699281e22131a3`.

## Files

- `full-run/`: complete runner report and all 23 suite logs.
- `media-integration-v0.3.2.log`: isolated real-framework media checks.
- `release-ui-renders.json`: production board and integrated robot render manifest.
- `robot-personality-renders.json`: direct character states, motion delta, Reduce Motion and cleanup evidence.
- `build-receipt-v0.3.2.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.2.json`: exact public asset identity prepared for release.
- `app-store-preflight-static-v0.3.2.log`: static Store packaging result.
- `app-store-preflight-release-v0.3.2.log`: external signing/tooling blockers.

The live camera-island geometry and external-display fallback were established on the same 0.3.1 feature source before this updater-only hotfix. That evidence remains in `../0.3.1/live-camera-island-v0.3.1.json` and `../0.3.1/live-robot-below-camera-island.png`.
