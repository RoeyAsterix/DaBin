# Direct-install Gatekeeper failure

The public 0.3.18 Apple Silicon and update ZIP files are byte-identical to the verified release assets, preserve executable permissions, contain ARM64 macOS 14+ binaries, and pass `codesign --verify --deep --strict`. They are not valid public direct-install artifacts.

Both the main app and updater use ad-hoc signatures with no Team Identifier. Neither has a notarization ticket. A browser or messaging-app download applies `com.apple.quarantine`; Gatekeeper then rejects the app before launch. This reproduces the user's **“Apple could not verify … is free of malware”** dialog.

## Evidence

- Public standalone SHA-256: `2dd604b8a4eb7f146c75f0efd223ecd3e95085a7a64b3fedeb89925fa2870201`
- Main and updater executable modes after both `ditto` and ZIP extraction: `0755`
- Main architecture: `arm64`
- Bundle version: `0.3.18 (43)`
- `codesign --verify --deep --strict`: pass
- `codesign -dv`: `Signature=adhoc`, no `TeamIdentifier`
- `spctl --assess --type execute`: rejected
- `syspolicy_check distribution`: fatal `Notary Ticket Missing`
- `xcrun stapler validate`: no ticket
- Available signing identities on the release host: zero

## Required production correction

The embedded updater must be signed first and the outer app second with a **Developer ID Application** identity, hardened runtime, and secure timestamps. Apple notarization must succeed, the ticket must be stapled, and a fresh quarantined download must pass `codesign`, `stapler`, `spctl`, and `syspolicy_check` before the release is called a direct installer.

Changing ZIP, DMG, or PKG format alone cannot satisfy Gatekeeper. The release process must refuse to publish an ad-hoc or unnotarized package as a public installer.
