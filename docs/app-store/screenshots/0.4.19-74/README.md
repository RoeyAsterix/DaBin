# Current DaBin App Store screenshot drafts

This isolated exporter prepares three 1440 × 900 opaque RGB PNGs from the current production native interface and canonical Quiet Orbit robot:

- `DABIN__APP_STORE__01_INBOX.png` — save useful bits and organize later.
- `DABIN__APP_STORE__02_PROJECTS.png` — project color frames and the real Explorer preview.
- `DABIN__APP_STORE__03_FOCUS.png` — one task and its visible focus-duration controls. Checklist and attachment sections are lower in the real detail view and are not claimed as visible in this screenshot.

The pale background and friendly headline/subtitle are marketing composition. All app content and controls are actual `BoardView`/`RobotAppFrameView`, not recreated UI. The robot is the real `RobotCharacterView`. Landscapes are original code-drawn fictional fixture images adapted from the existing local guide exporter.

## Render only after coordinated final QA

The final test run contains timing-sensitive native-window suites. Do not run this exporter during that run. After the main agent releases rendering, use the bundled Python runtime:

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/app-store/screenshots/0.4.19-74/export_screenshots.py --render
```

The script refuses a changed version/build, finds a current-source-hash-verified Release QA module, verifies its library/module hashes, compiles with warnings as errors, renders its own nonactivating offscreen windows, checks source/resources again, and verifies every PNG's dimensions, nonblank content and RGB/no-alpha encoding. The native AppKit snapshot uses RGBA, requires a fully opaque canvas and is exported as RGB without resampling. It records `manifest.json` plus `native-renders.json` with source, helper, module and output hashes.

No KARI assets, personal captures, real clipboard, installed application, standard preferences, notification delivery, permission prompts, global input or network requests are used. The fixture archive and named preference domain are temporary. Auto Capture and website previews stay off; the focus timer is configured but not running. The existing `../1440x900/` screenshot set and all guide/PDF source assets remain untouched.

Main-agent original-resolution visual review of all three final images passed as **source-matched DRAFTS**. The Focus caption was narrowed to the visible duration controls; it does not imply that cropped checklist/attachment content is shown.

These are not upload-approved or submitted screenshots and not proof of Apple approval. Compare the controls, native artwork and behavior with the exact distribution-signed sandbox candidate before upload. Confirm imagery rights and current metadata. No upload is performed by this exporter. `export-attempts.json` records the rejected sandbox/24-bit-capture attempts separately.
