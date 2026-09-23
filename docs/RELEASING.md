# Releasing DaBin

The direct channel and Mac App Store are separate builds. The standalone build enables `DABIN_DIRECT_UPDATES` and embeds `DaBin Update.app`. The generated Xcode Release configuration does neither; a Mac App Store build must use Apple’s update channel.

## Direct GitHub release

1. Increase `CFBundleShortVersionString` and the monotonically increasing `CFBundleVersion` in `native/Resources/Info.plist`.
2. Run full QA in an unlocked macOS session.
3. Build the optimized direct app:

   ```sh
   cd native
   ./scripts/build.sh
   ```

4. Create the package and public update manifest:

   ```sh
   python3 UpdateTools/package_update.py \
     --output ../output/downloads/DaBin-VERSION-Update.zip \
     --guide ../output/pdf/DaBin-Quick-Guide.pdf \
     --release-manifest ../output/downloads/DaBin-update.json
   ```

   The packager tests fresh install, replacement, backup, signature, ZIP extraction, package-mode install, executable hash, and source freshness in temporary locations.

5. Commit the exact source and documentation, tag that commit `vVERSION`, and push both.
6. Create a GitHub Release for the tag with these assets:

   - `DaBin-VERSION-Update.zip`
   - `DaBin-update.json`
   - `DaBin-Quick-Guide.pdf`

7. Verify that `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json` returns the released manifest and that its size and SHA-256 match the ZIP asset.
8. In the installed app, open **Settings → Software updates** and check the live feed.

Never edit `DaBin-update.json` after packaging. Rebuild and create a new version if the application or archive changes. Do not reuse a tag or overwrite a published asset.

## Distribution status

The local package can update the owner’s present installation. Public distribution to other Macs needs Developer ID signing, hardened runtime validation, notarization and stapling. No workflow should advise disabling Gatekeeper.
