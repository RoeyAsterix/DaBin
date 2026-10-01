# DaBin App Store preparation — 2 October 2026

Source: **0.4.19 (74)** · `com.dabin.mac` · Team `8QG4967CSU`

[Machine-readable final summary](summary.json) · [Applicable-guideline review](../../../native/APP_STORE_READINESS.md) · [Listing/reviewer draft](../../app-store/APP_STORE_CONNECT_DRAFT.md)

**Functional regressions and unsigned Store packaging pass. NOT ready to submit.** This is evidence for the current source, not Apple approval or proof of signed Sandbox runtime behavior. Two privacy offscreen bottom captures failed visual QA and are withheld, separately from the passing assertions.

## Final verified results

| Check | Result | Evidence |
| --- | --- | --- |
| Full registered native Release regression | 73/73 suites; 87,546 reported assertions; zero failures | [Final tests and scope](tests/README.md), [full receipt](tests/full-release-final/report.json) |
| Synthetic PDF/document/moving-video integration | 39/39; network disabled | [Final media receipt](tests/media-integration-final-report.json) |
| Offline Python | 77 tests: 30 distribution + 15 metadata + 32 Store preflight | [Post-packaging log](tests/offline-python-post-packaging.log), [Store regressions](tests/store-preflight-regressions.log) |
| Packaging-only archive correction | 27 scoped UpdateConfiguration checks | [Scoped receipt](packaging/scoped-update-configuration-report.json) |
| Final unsigned Xcode Store Release | Compiles; 51/51 packaging checks; exact current resources; no direct updater/helper | [Packaging evidence](packaging/README.md), [build receipt](packaging/unsigned-store-candidate-receipt.json) |
| English listing draft | 13 local limits/version checks pass; completeness intentionally fails with 12 unresolved checks | [Draft checks](metadata/draft-checks.json), [submission completeness](metadata/submission-completeness.json) |
| Privacy source audit | Updated manifest/policy/date/manual-preview consent; public-policy parity still pending | [Audit](privacy/privacy-source-audit.json) |
| Policy-view offscreen QA | 11 assertions pass; two top/date views visually pass; both bottom captures visually fail/are withheld due clipping | [Provenance and limitations](privacy/privacy-render-provenance.json) |
| Current screenshots | Three fictional-data, native-interface 1440 × 900 RGB drafts, visually inspected | [Drafts and provenance](../../app-store/screenshots/0.4.19-74/README.md) |

The native full test module enables `DABIN_DIRECT_UPDATES`; Store-only compilation is separately verified. Pixel/animation assertions account for much of the reported count. The later script-only archive-entitlement correction did not change the full run's native/resource/Swift-test inputs and has separate regression evidence.

Host: ARM64 macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), SDK 27.0, Swift 6.4. The target is macOS 14; no macOS 14 machine was tested. Screenshots use the verified test module, not a distribution-signed binary.

## Changes made

- Added file-timestamp reason `C617.1` for DaBin-owned originals/preview cache checks.
- Disclosed locally visible project-name and three-word task-title robot signs.
- Derived the policy sheet's update date from its bundled document rather than a stale hardcoded date.
- Clarified that optional network previews apply only to manually saved links.
- Removed default provisioning-download authorization from the archive helper.
- Strengthened exact source/resource, Store code/payload, minimal entitlements, team/profile/certificate and recursive quarantine gates.
- Added a safe isolated unsigned Store builder, 32 offline packaging tests and 15 metadata tests.
- Rewrote friendly current listing/reviewer notes and prepared current native screenshot drafts.

## Signing and external gates

Existing Apple Development, Apple Distribution and a matching unexpired Store profile were inspected read-only. **The Mac Installer Distribution identity is missing.** Xcode archive preparation compiled, but existing-key signing required owner approval in macOS. Only this task's waiting build/signing processes were safely stopped; derived data/logs remain preserved. No completed signed archive, Store installer or upload is claimed. A residual system dialog, if still visible, can be dismissed by the owner; no signing client remains. Exact final signing/cleanup status is in [packaging-status.json](packaging/packaging-status.json).

The current public privacy policy is reachable but still contains the older 1 October text. Publication of the corrected policy needs a separately authorized step. Support/legal publisher, pricing, review contact and regional declarations are not invented.

Before submission:

1. Resolve signing authorization/assets and validate the exact distribution-signed installer in Xcode/App Store Connect.
2. Confirm the Connect app/name/Bundle ID/version history, real support/contact/legal rights, price and territories.
3. Publish/verify policy parity and complete current privacy, age, encryption, accessibility and applicable trader/agreement/tax/banking forms.
4. Test the signed Sandbox app on macOS 14 and current macOS: clean install/update, capture and file access, permission restoration/revocation, monitoring consent/indication/Pause/Off/Quit, preview network isolation and IPv6-only/offline operation, reminders, VoiceOver/keyboard, motion/transparency, multiple displays and idle/active energy/CPU/memory/disk use.
5. Compare/recapture screenshots against that exact product, then complete upload processing and Apple's review. TestFlight is a recommended project QA route, not a mandatory prerequisite for production review. [Apple's upload workflow](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

See the [full applicable-guideline review](../../../native/APP_STORE_READINESS.md) and [submission draft](../../app-store/APP_STORE_CONNECT_DRAFT.md). Apple, not this audit, determines approval under its [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Evidence integrity and privacy

Production build fingerprint: `cd0a8ef9a095df3090991077c35ef5534d2a18a5cf75f05d1fb6f21a5e88d1be`.

Full QA fingerprint: `9039172fca3d6b400c7ed1ec3ecd1551210d7eca23cd69a524c1efb00893e3fe`. Full receipt SHA-256: `7a4521e405437c7d3ce93715d85f5246f06e315addf28b0cd82fb90b00787bfa`.

Unsigned Store executable SHA-256: `8f60d225de40822c84c5afa7c13aee1c386680bfe7ec89462b2cd4573c98396e`.

Different fingerprints describe different inventories; they are not interchangeable. Receipts bind their exact inputs. Preliminary tool-Sandbox failures, rejected screenshot-format outputs, signing configuration failures and File Provider metadata failure are retained/explained separately; they are not silently counted as passing runs.

Published diagnostics retain machine-local paths and public signing/profile identifiers as historical provenance, not credentials or proof of distribution approval. The personal signing subject in two development archive logs is redacted and trailing whitespace is normalized in four archive logs; untouched originals remain locally in ignored `output/publication-private-originals/`. Generated apps, SDK caches, private keys and personal capture archives are not committed.

No installed app/personal archive/settings, general clipboard, real reminder delivery, account/keychain permissions or public release was changed. Native fixtures use temporary fictional data and own windows; some focus tests temporarily activate their own process. No KARI asset was read or sent externally. Nothing was uploaded, pushed, published or submitted.

The legacy standalone privacy-render helper has dependency/copy drift; this audit uses a docs-only helper linked to the verified native QA module instead. Its bottom offscreen snapshots still clip the pinned heading/Done control and are retained as rejected candidates, not delivery images or established production defects. Live scrolling in the exact signed app remains pending. No retry or signing job is left running.
