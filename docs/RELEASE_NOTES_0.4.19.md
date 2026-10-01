# DaBin 0.4.19 (74): smooth window corners and resize grips

The compact and expanded board now share one continuous 21-point corner curve. The hosted content, reveal mask, finishing outline and thin metallic rim follow that same shape, so the native frame no longer adds a mismatched circular clip. Native vectors and masks follow the window's backing scale when it moves between displays. The rim is vector-only rather than a full-surface gradient/mask; no live frame-rate improvement is claimed.

Resize grips now follow the visible card edges and extend through the transparent chrome to the physical outer corners. The shallow inner band is six points, with twelve-point corner padding reach. This makes a full safe-area expanded window resizable inward while keeping the close button, project controls and ordinary content actions clickable. Chrome dragging, expansion and restoration retain their existing behavior.

Two-second transient messages, preview-led Explorer/collection cards, the click-to-dismiss task alarm, project colors, tooltips and the existing 0.78-second closing choreography are retained. Reduce Motion still uses the short 0.14-second closing fade.

## Verification and local installation

All **18 selected Release suites pass across two frozen-input reports**: 17 valid passing suites from the [batch](../native/build/qa/runs/20261001T215857193709Z/report.json), excluding its failed close recording, and the [final focused closing suite](../native/build/qa/runs/20261001T221215692673Z/report.json) with **400 checks**. Current production matches the passing-suite inputs and frozen build. This is targeted coverage assembled from the two reports, not a claim that the earlier batch itself was all green.

Earlier expanded CPU recordings intermittently missed frame density or the narrow late-fade interval. The vector rim avoids the full-surface composite; a [separate vector run](../native/build/qa/runs/20261001T215719866001Z/report.json) passed 372 unchanged checks. The final test-only sampler now schedules from before rendering, gives the run loop 1 ms when overdue and captures presentation metadata before CPU rendering. It retains at least 12 moving frames, eight changed frames, gaps below 0.12 seconds and full native 2× encoding. A second actual close checks the original opacity thresholds at observed times—above 0.95 in the 60–78% hold band and below 0.8 in the 90–100% fade band—plus finite uniform scale and a once-only hidden endpoint. No production motion contract or threshold was weakened. These previews do not measure live compositor FPS.

The chrome suite passes **50,904 assertions**, mostly native mask-pixel checks. It exercises **16 actual resize drags** across all eight handles in compact and expanded windows, opposite-anchor preservation, release cleanup, shallow/physical hit areas, header control padding, movement and expansion dispatch. Eight actual Board fixtures cover 380×500 and 1200×800 content in light/dark at 1×/2×, with matching mask PNGs. Shared paths, transparent wrapper behavior and immediate backing-scale updates pass. All four corners have consistent antialias coverage: 45 fractional-alpha pixels at 1× and 95 at 2×. [Chrome evidence](../native/build/qa/window-chrome/240AD841-8F51-4356-96A0-210E88B8CE3F/report.json).

**0.4.19 (74) is installed and running locally.** Strict signatures and installed app/helper executable hashes match the frozen ARM64 build. Settings confirms the version, tooltips remain enabled and Auto Capture remains paused. The retained project and compact Explorer were restored after Expand/Restore. The previous 0.4.18 app was quit normally and backed up before guarded replacement. The installer did not modify the archive; the personal archive was not independently byte-inventoried. [Installation evidence and scope](qa/local-install-0.4.19-2026-10-02/verification.json).

No downloadable or notarized 0.4.19 release is published. Public downloads still contain **0.3.18**; publishing source and documentation does not update those packages.

The later [2 October App Store preparation](qa/app-store-2026-10-02/README.md) updates privacy resources and packaging tools without replacing the installed app above. Its complete 73-suite Release run and unsigned Store packaging pass; signed export, runtime verification and owner/Connect fields remain pending. See the [current readiness](../native/APP_STORE_READINESS.md) for submission gates.

## Actual native QA previews

These four previews from the final 400-check run record actual production Core Animation presentation frames in isolated fictional-data windows at 2×. They are CPU-sampled QA previews, not live FPS measurements or desktop recordings.

- [Compact light closing preview](../native/build/qa/robot-close-visual/113F60CA-1C5F-4E11-A328-F1AF4DAE0F6B/DaBin-Robot-Close-380x500-light@2x.mp4)
- [Compact dark closing preview](../native/build/qa/robot-close-visual/113F60CA-1C5F-4E11-A328-F1AF4DAE0F6B/DaBin-Robot-Close-380x500-dark@2x.mp4)
- [Expanded light closing preview](../native/build/qa/robot-close-visual/113F60CA-1C5F-4E11-A328-F1AF4DAE0F6B/DaBin-Robot-Close-1200x800-light@2x.mp4)
- [Expanded dark closing preview](../native/build/qa/robot-close-visual/113F60CA-1C5F-4E11-A328-F1AF4DAE0F6B/DaBin-Robot-Close-1200x800-dark@2x.mp4)
