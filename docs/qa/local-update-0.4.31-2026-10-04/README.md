# Local DaBin update — 0.4.31 (86), 4 October 2026

**Installed and reopened successfully:** `/Users/roeylibfeld/Applications/DaBin.app`.

This is the normal local/direct channel, built from the verified frozen 0.4.31 preparation source. It includes the persistent recording indicator and corrected privacy text while retaining the local updater. It does not resolve App Store signing/submission gates. Separate tutorial work in the shared checkout remains preserved and excluded.

## Verification

- Release ARM64 build succeeded with warnings as errors and a local ad-hoc signature.
- Installed main executable and embedded updater hashes exactly match the build receipt; strict deep code-signature verification passed.
- Five focused direct-channel suites have passing results: privacy 38, application lifecycle 77, native tooltip 31, updater 34 and update configuration 41 — **221 checks** total.
- The first run passed 4/5. The updater test had inherited unrelated tutorial assertions from shared source, although that feature was intentionally excluded from the frozen production candidate. Restored only the candidate test's verified baseline direct branch, kept the Store branch unchanged, and reran successfully. No production or shared tutorial file changed. The failed compilation, original test and corrective patch remain in this directory.
- Installer first refused while the old DaBin process was running. Quit through the app, then the guarded installer succeeded and retained the prior app in its backup directory.
- Live Settings shows **DaBin 0.4.31 (86)** with the direct updater idle. All 60 saved items across 8 date groups remain visible. Auto Capture remains paused; clipboard/screenshot channel selections, selected screenshot folder, existing quick-capture draft and link-preview preference were preserved. Returned to the pre-update blank Search view.
- The first desktop-state lookup timed out after 5 seconds as the new app opened. The next lookup and subsequent Settings/Search verification succeeded promptly; the app remains running.

## Evidence and rollback

[Verification](verification.json), [build receipt](build-receipt.json), [build log](build.log), [successful installation](install-retry.log), [test-scope correction](test-scope-correction.json), [corrective patch](isolated-test-scope.patch).

The previous version is preserved at:
`/Users/roeylibfeld/Applications/.DaBinBackups/20261004-083205-3d498817.app`

The source snapshot is `native/build/store-preparation-20261004/native`. Its production build fingerprint still matches the earlier Store preparation. The local and Store executables intentionally differ because only the local channel contains the direct updater. No external update check, upload or App Store submission was performed.
