# DaBin 0.3.3 release evidence

This directory records the final source, functional, visual, package, PDF and Store-readiness checks for DaBin 0.3.3 (28).

## Results

- **23/23** registered optimized suites passed, covering **1,923 checks**.
- **28** production board renders, **10** direct native robot renders and **8** additional empty Daily/Weekly renders passed.
- Daily at 380 points and Weekly at 800, 900 and 1,440 points were inspected in light and dark appearances. The segmented control is readable, selected state is clear, and the centered date/range remains unobstructed.
- The one-page A4 PDF passed extraction, paragraph-bound checks and full-page PNG inspection. Repository and distribution copies are byte-identical.
- Static App Store packaging passed **20/20**. Release preflight is blocked only by the missing Apple Developer Team ID and full Xcode.
- The ARM64 Release build is 0.3.3 (28), source fingerprint `5e265bbda90bc9f4f7d82e5e2fb1a4cbb4134e61ab719abc7f7bd7379a9a3af9`, executable SHA-256 `23bac4cf61a4f960198edc1e04fd41490aef843c99dce9ac0a69018dfe677411`.
- The verified update ZIP is 2,942,317 bytes with SHA-256 `36048bd1248c2cfd2593ef2282c121cf2e4d76edbb1a9f3ab7349def6599ce23`.
- Update packaging passed isolated fresh install, replacement, backup, signature, extraction and downloaded-package checks.

## Files

- `full-run/`: complete runner report and all 23 suite logs.
- `release-ui-renders.json`: 28 production board views and 10 direct native robot artifacts.
- `weekly-entry-renders.json`: 8 empty Daily/Weekly views in light and dark appearances.
- `native-view-*.png`: representative original render outputs used for direct visual inspection.
- `quick-guide-layout-check.json`: extracted guide text and bounded paragraph geometry.
- `build-receipt-v0.3.3.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.3.json`: exact update asset identity prepared for release.
- `app-store-preflight-static-v0.3.3.log`: static Store packaging result.
- `app-store-preflight-release-v0.3.3.log`: external signing/tooling prerequisites.

Publication, live update, installed-app identity and archive-preservation evidence is added after the immutable release assets are public.
