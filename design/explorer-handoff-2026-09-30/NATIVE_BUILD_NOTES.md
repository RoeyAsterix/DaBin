# Build the included native source

The `native/` directory is a snapshot of the complete application runtime source, bundled resources, direct-update helper source, and three local build scripts from the feature implementation. `SOURCE_SNAPSHOT.json` records the exact file hashes and version at packaging time. The source was copied from the working tree, including the new Explorer files, so it includes changes beyond the last Git commit.

## Local build

Use an Apple Silicon Mac with Xcode and its command-line tools selected, Python 3, and the macOS SDK. The source targets ARM64 macOS 14+. Current development verification uses Xcode 27 and macOS 26.6.2; this does not establish runtime verification on every supported OS.

From the extracted handoff root:

```sh
cd native
./scripts/build.sh
```

The script builds an optimized application at `native/build/DaBin.app`, embeds the direct-update helper, applies local ad-hoc signing by default, and writes a build receipt. Runtime dependencies are Apple system frameworks. A signed/notarized public download or App Store submission requires the separate distribution pipeline and account configuration.

For an unoptimized local development build:

```sh
./scripts/build.sh --configuration Debug
```

Use the included synthetic reference renders to review the existing app. Launching the standard bundle uses the normal DaBin data location for that Mac; prototype fixtures should be isolated from real captures. The upstream native QA harness owns fixture stores, pasteboards, and rendering; these test runners are not included in this design package.

## Scope of this snapshot

Included: `Sources/DaBin/*.swift`, tracked `Resources/`, `UpdateTools/DaBinUpdater.swift`, and `scripts/build.sh`, `build_app.py`, `project_inventory.py`.

The handoff excludes compiled applications, database/clipboard contents, personal captures, signing credentials, provisioning profiles, test runners, installers, publishing scripts, and the Xcode project. Those workflows remain in the original repository. Read `IMPLEMENTATION_STATUS.md` for the upstream tests that were actually run.

The original build inventory hashes every repository build script. This focused snapshot contains only the three scripts needed for a standalone local build, so rebuilding it produces its own source fingerprint. Compare runtime/resource hashes in `SOURCE_SNAPSHOT.json` when checking equivalence to the feature implementation.
