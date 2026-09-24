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
5. Build the optimized direct app:

   ```sh
   cd native
   ./scripts/build.sh
   ```

6. Create the update package, public update manifest, and separate manual-install package:

   ```sh
   python3 UpdateTools/package_update.py \
     --output ../output/downloads/DaBin-VERSION-Update.zip \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf \
     --release-manifest ../output/downloads/DaBin-update.json

   python3 scripts/package_standalone.py \
     --output ../output/downloads/DaBin-VERSION-AppleSilicon.zip \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf

   python3 scripts/stage_release_assets.py \
     --update ../output/downloads/DaBin-VERSION-Update.zip \
     --standalone ../output/downloads/DaBin-VERSION-AppleSilicon.zip \
     --manifest ../output/downloads/DaBin-update.json \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf \
     --notes ../docs/RELEASE_NOTES_VERSION.md \
     --output-directory ../output/releases/vVERSION
   ```

   The update packager tests fresh install, replacement, backup, signature, ZIP extraction, package-mode install, executable hash, and source freshness in temporary locations. The standalone packager verifies its ARM64 app, strict signature, executable hash, per-file manifest, source freshness, and ZIP round trip. Its README directs manual installations to `~/Applications/DaBin.app`, which is the same location used by in-app updates. The staging tool verifies that the public manifest describes the exact update bytes, then creates byte-identical `DaBin-Latest-Update.zip` and `DaBin-Latest-AppleSilicon.zip` aliases alongside the versioned packages. It refuses to replace an existing staging directory.

7. Commit the exact source and documentation, tag that commit `vVERSION`, and push both.
8. Create a GitHub Release for the tag with these assets:

   - `DaBin-VERSION-Update.zip`
   - `DaBin-Latest-Update.zip`
   - `DaBin-VERSION-AppleSilicon.zip`
   - `DaBin-Latest-AppleSilicon.zip`
   - `DaBin-update.json`
   - `DaBin-Quick-Guide.pdf`
   - `RELEASE_NOTES_VERSION.md`

   Upload every file from `output/releases/vVERSION` in the initial release command and publish it as a normal, non-prerelease release. The repository workflow also recreates the two stable aliases from the versioned assets when a release is published; a manual workflow run can repair an older release. A workflow failure is a release failure and must be resolved before announcing the download.

9. Verify that all three permanent URLs return HTTP 200 without authentication:

   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json`
   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip`
   - `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip`

   Confirm that each stable ZIP is byte-identical to its versioned asset, that the manifest size and SHA-256 match the versioned update ZIP, and that the executable in both package types matches the build receipt. `/releases/latest` follows the newest non-draft, non-prerelease GitHub release, so do not mark a release latest until these checks pass.
10. In the installed app, open **Settings → Get updates** and check the live feed.

Never edit `DaBin-update.json` after packaging. Rebuild and create a new version if the application or archive changes. Do not reuse a tag or overwrite a published asset.

## Distribution status

The local package can update the owner’s present installation. Public distribution to other Macs needs Developer ID signing, hardened runtime validation, notarization and stapling. No workflow should advise disabling Gatekeeper.
