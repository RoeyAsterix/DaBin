# Releasing DaBin

The direct channel and Mac App Store are separate builds. The standalone build enables `DABIN_DIRECT_UPDATES` and embeds `DaBin Update.app`. The generated Xcode Release configuration does neither; a Mac App Store build must use Apple’s update channel.

## Direct GitHub release

1. Increase `CFBundleShortVersionString` and the monotonically increasing `CFBundleVersion` in `native/Resources/Info.plist`.
2. Update `CHANGELOG.md`, create `docs/RELEASE_NOTES_VERSION.md`, and update user-facing guides and privacy text for behavior or data-flow changes.
3. Regenerate and verify the Xcode project so every new Swift source is present:

   ```sh
   cd native
   python3 scripts/generate_project.py
   python3 scripts/generate_project.py --check
   ```

4. Run full QA in an unlocked macOS session. For robot-placement or motion changes, cover real built-in camera-island geometry, no-island display fallback, all interaction/result states, hidden-state cleanup and Reduce Motion.
5. Confirm that the release Mac has an unexpired **Developer ID Application** certificate and a `notarytool` keychain profile. The profile must already contain the Apple notarization credentials; keep credentials out of the repository and command history. List the available signing identities with:

   ```sh
   security find-identity -v -p codesigning
   ```

   The public packager accepts only the exact `Developer ID Application: … (TEAMID)` identity. Apple Development, Apple Distribution, and ad-hoc identities are refused.

6. Build the optimized direct app, then run the fail-closed public distribution packager:

   ```sh
   cd native
   ./scripts/build.sh

   python3 scripts/package_notarized_distribution.py \
     --identity 'Developer ID Application: OWNER (TEAMID)' \
     --notary-profile DaBin-notary \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf \
     --output-directory ../output/notarized/vVERSION
   ```

   The script first binds the Release app, embedded updater, architecture, deployment target, versions and executable bytes to the fresh build receipt. It signs the embedded updater first and the outer DaBin app second, always with hardened runtime and a trusted timestamp. It submits one archive containing the complete outer app through `notarytool`, waits for an `Accepted` result, staples the outer app, and checks the nested signature plus outer `stapler`, `spctl`, and `syspolicy_check` results. It repeats the outer signature, ticket, executable hashes and launch-policy checks after both `ditto` ZIP round trips. The round-tripped embedded updater then installs that exact update ZIP twice into an isolated destination; the packager verifies the replacement backup and checks the installed and backed-up apps through the same signature, ticket and policy gates. A private sibling staging directory is published only through exclusive atomic rename after every gate passes, so a concurrent destination is preserved.

   The verified output directory contains:

   - `DaBin-VERSION-Update.zip`, the package consumed by DaBin's built-in updater
   - `DaBin-VERSION-AppleSilicon.zip`, the first-install package containing `DaBin.app`
   - `DaBin-update.json`, whose size and SHA-256 describe the exact update ZIP
   - `DISTRIBUTION-ATTESTATION.json`, which records the signing team, notarization submission ID, artifact hashes, and successful gates

7. Stage the verified packages with their permanent aliases:

   ```sh
   python3 scripts/stage_release_assets.py \
     --update ../output/notarized/vVERSION/DaBin-VERSION-Update.zip \
     --standalone ../output/notarized/vVERSION/DaBin-VERSION-AppleSilicon.zip \
     --manifest ../output/notarized/vVERSION/DaBin-update.json \
     --attestation ../output/notarized/vVERSION/DISTRIBUTION-ATTESTATION.json \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf \
     --notes ../docs/RELEASE_NOTES_VERSION.md \
     --output-directory ../output/releases/vVERSION
   ```

   The staging tool verifies the manifest, notarization attestation, signed executable hashes, updater-installation QA and exact package hashes before creating byte-identical `DaBin-Latest-Update.zip` and `DaBin-Latest-AppleSilicon.zip` aliases. It refuses to replace an existing staging directory.

8. Commit the exact source and documentation, tag that commit `vVERSION`, and push both.
9. Create a GitHub Release for the tag with these assets:

   - `DaBin-VERSION-Update.zip`
   - `DaBin-Latest-Update.zip`
   - `DaBin-VERSION-AppleSilicon.zip`
   - `DaBin-Latest-AppleSilicon.zip`
   - `DaBin-update.json`
   - `DISTRIBUTION-ATTESTATION.json`
   - `DaBin-Quick-Guide.pdf`
   - `RELEASE_NOTES_VERSION.md`

   Upload every file from `output/releases/vVERSION` in the initial release command and publish it as a normal, non-prerelease release. The macOS repository workflow downloads the exact versioned packages, requires the attestation, verifies hashes and updater QA, reapplies signature, ticket, quarantined Gatekeeper and system-policy checks, and only then recreates the two stable aliases. A manual workflow run can repair a release that already satisfies those gates. A workflow failure is a release failure and must be resolved before announcing the download.

10. Verify that all four permanent URLs return HTTP 200 without authentication:

   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json`
   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DISTRIBUTION-ATTESTATION.json`
   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip`
   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip`

   Confirm that each stable ZIP is byte-identical to its versioned asset, that the manifest size and SHA-256 match the versioned update ZIP, and that both packages match the post-sign executable hashes and artifact hashes in the distribution attestation. The packager separately proves that the pre-sign source matched the build receipt. `/releases/latest` follows the newest non-draft, non-prerelease GitHub release, so do not mark a release latest until these checks pass.
11. Download the public ZIP from GitHub on a clean macOS account, extract it normally, and repeat `codesign`, `stapler validate`, `spctl --assess --type execute`, and `syspolicy_check distribution` on the downloaded `DaBin.app`. Then complete a fresh install and an in-app replacement without changing macOS security settings.
12. In the installed app, open **Settings → Get updates** and check the live feed.

Never edit `DaBin-update.json` after packaging. Rebuild and create a new version if the application or archive changes. Do not reuse a tag or overwrite a published asset.

## Local package QA

`UpdateTools/package_update.py` and `scripts/package_standalone.py` remain local test packagers. They can exercise the installer and ZIP layouts with an ad-hoc build on the current Mac, but their output is not a public release artifact and must not be uploaded to GitHub Releases. Their manifest and README intentionally disclose the ad-hoc, unnotarized status.

Run their focused local checks when changing installer behavior. Run the public distribution script above for every package offered to another Mac. It provides no `--skip-notarization`, `--ad-hoc`, or force-output option; rejected notarization, missing tickets, wrong signatures, failed Gatekeeper assessment, failed distribution policy, existing output, and stale builds all stop before delivery.

The public pipeline's offline refusal and command-construction tests do not contact Apple:

```sh
cd native
python3 -m unittest -v Tests/test_notarized_distribution.py
```

## Distribution status

Only artifacts produced by `package_notarized_distribution.py` and independently rechecked after download qualify for direct public distribution. Never advise a user to bypass or disable Gatekeeper. A verification failure is a release failure.
