# Store packaging evidence - 2 October 2026

DaBin **0.4.19 (74)**, bundle `com.dabin.mac`, Team `8QG4967CSU`.

The final frozen Store source compiles as an unsigned Release ARM64 app and
passes **51/51 packaging checks**. This is a compile/packaging intermediate,
**not** an App Store distribution product, validation result or Apple approval.

## Exact final unsigned build

- App: `build/app-store-2026-10-02/unsigned-final/derived-data/Build/Products/Release/DaBin.app`
- Source fingerprint: `cd0a8ef9a095df3090991077c35ef5534d2a18a5cf75f05d1fb6f21a5e88d1be`
- Executable SHA-256: `8f60d225de40822c84c5afa7c13aee1c386680bfe7ec89462b2cd4573c98396e`
- Inputs were unchanged before/after build and still match the receipt.
- Xcode 27.0 (27A266a), SDK 27.0, Swift 6.4; ARM64, macOS 14 minimum.
- No direct updater/helper/feed; real Store-managed update implementation.
- Exact current privacy manifest, offline privacy policy and ICNS icon packaged.
- Linked dependencies are Apple system frameworks/libraries only.
- Unsigned code does not establish sandbox runtime behavior or distribution readiness.

See [unsigned receipt](unsigned-store-candidate-receipt.json),
[packaging preflight](unsigned-packaging-preflight.log) and
[system dependencies](final-store-system-dependencies.log).

## Checks and packaging-only correction

- Final static preflight: **30/30**.
- Final environment preflight: **33/33**; URL checks are syntactic, not reachability/contact validation.
- Store tooling regression tests: **32/32**.
- Scoped `UpdateConfigurationTests`: **27 checks**, passed after the narrow packaging-only correction.

The standard development archive can legitimately have only the four basic
sandbox entitlements, without Store application/team entitlement claims.
The preflight now requires those claims and an embedded Store profile only for
`--app` distribution inspection. `--archive-app` continues to require the
development signing identity, configured signature TeamIdentifier, strict
signature, sandbox capabilities, no debugger entitlement, current source
fingerprint, correct resources, and absence of direct-update payload/code.
Two dedicated regressions cover the archive/distribution distinction.

This changed packaging scripts/tests only. The final full 73-suite native QA
receipt remains separately preserved; native Swift, production resources and
Swift test inputs did not change after that run.

## Signing/archive status

Existing public certificate metadata confirms valid Apple Development,
Apple Distribution and Developer ID Application identities. The Apple
Development certificate's OU is Team `8QG4967CSU`; the parenthetical value in its
name is not its team. The cached Store profile is for
`8QG4967CSU.com.dabin.mac`, expires 27 September 2027 and includes the available
Apple Distribution certificate. **No valid Mac Installer Distribution identity
is available**, so Store installer export is not ready.

Preserved attempts:

1. Manual Xcode archive with the Xcode-managed Store profile: rejected before compilation.
2. Automatic archive pinned to Apple Distribution: conflicting signing settings, rejected before compilation.
3. Standard Apple Development archive with workspace-derived build products:
   compiled, but code signing rejected File Provider/Finder metadata.
4. Final standard Apple Development archive uses **all DerivedData and build
   products under the owned `/private/tmp` directory**. Compilation completed;
   signing waited for owner approval of macOS's existing-key authorization dialog.
   No approval arrived, so only this task's verified `codesign` and `xcodebuild`
   processes were stopped. Approval is **still required, not declined**.

Requested final archive (not created; partial DerivedData preserved):
`/private/tmp/DaBin-AppStore-2026-10-02-SWUyJN/DaBin-0.4.19-74-development-final.xcarchive`.

No private keys, account settings, provisioning assets or installed app were
changed. No provisioning download flags, signing timestamp requests, export,
upload, submission, custom post-archive re-sign or installer package was used.
No completed archive or archive ZIP is claimed. Session 55360 ended with exit
143 after scoped SIGTERM; own `codesign` PID 91735, `xcodebuild` PID 91563 and
its build worker exited. The system's shared SecurityAgent was not terminated.

The `Store-ExportOptions--BLOCKED-missing-installer.plist` file is an unexecuted
local-export draft (`destination=export`, not upload). It must not be treated
as a completed distribution product or run without the owner's missing signing
asset and final validation steps.

This is a stopped, owner-blocked archive attempt, not a final archive receipt.
The owner can authorize the existing key on a deliberate rerun; any residual
macOS authorization dialog can be dismissed by the owner. See the main readiness
report for remaining App Store Connect, public-policy, listing and runtime review
gates, including the separate missing Installer identity.
