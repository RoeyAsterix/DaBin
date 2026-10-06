# Supplemental privacy view QA

Prepared for **0.4.41 (96)**. Execution is pending the final source freeze, exact Store Release QA module and root's release of the coordinated GUI stage. No supplementary compile or render has been performed by this preparation.

`run_privacy_render.py` links the unchanged `native/Tests/PrivacyRenderTests.swift` to the cached production module. It parses the selected `run_qa.py` for the literal module name; the current name is `DaBinTestCore`. It prepends only `@testable import MODULE` to a temporary wrapper. It does not recompile production sources or modify the original test.

The module receipt must match the selected source, runner, inventory, compiler, macOS SDK, Release configuration, Store compile conditions and exact library/module hashes. Candidate version and build must match selected `Info.plist`. Source, resources, policy, test and module hashes are checked again before and after execution. Changed inputs invalidate the result.

The fixture is a unique temporary `.app` under `/private/tmp` with a unique bundle identifier, its own Frameworks copy of the verified library, and the exact current bundled `PrivacyPolicy.md`. Fixture `Info.plist` deliberately omits public policy/support URLs because the original test checks that unconfigured links are absent. It is not a test of production URL configuration or sandbox/distribution signing. Native windows are offscreen and cannot become key/main; foreground preservation is asserted. The fixture does not construct the live coordinator, read a personal archive or clipboard, contact websites, request permissions, send notifications or monitor global input.

Run from the DaBin root with bundled Python after root releases this stage:

```bash
'/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3' docs/qa/full-review-2026-10-05/privacy-render-supplement/run_privacy_render.py --check-inputs --version 0.4.41 --build 96 --native-root /absolute/path/to/final/native --module-cache /absolute/path/to/final/native/build/qa-cache/exact-store-cache
```

The read-only input check compiles or renders nothing. Replace `--check-inputs` with `--run` only after explicit root release. Compilation uses the same Swift 5 target, warnings-as-errors, parse-as-library and optimized whole-module conditions as the selected Store QA runner. Each execution creates a fresh timestamp/UUID evidence directory under this folder's `runs/` with compile/runtime logs, provenance, native manifest and four original PNGs. The temporary bundle is removed when the run ends.

After a passing run, open all four images at original resolution:

- `privacy-policy-light-top.png`
- `privacy-policy-light-bottom.png`
- `privacy-policy-dark-top.png`
- `privacy-policy-dark-bottom.png`

Confirm the 5 October date, readable title/body, visible Done button, reachable bottom text and Show DaBin data folder button, appropriate light/dark contrast and no clipping. Automated assertion success leaves `visualReview` pending until this inspection. Public-policy parity remains pending separately; HTTP 200 serving the older 4 October policy is not parity.

## Optional integration render routes

`NativeRenderTests.swift` has early `--open-design`, `--explorer`, `--responsive-detail` and `--buddy-redesign` routes using fictional temporary archives, named injected preference suites, previews off, blocked clipboard reads and a blocked notification client. These return before its legacy `UserDefaults.standard` preview-preference mutation. A generic no-argument run or later legacy route should not be used as a safe substitute. Further renderer integration requires coordination and review of every default dependency.

`WalkthroughRenderTests.swift` uses a fictional temporary archive, named theme/preview preferences and an injected Day Export text writer, but constructs `AppState` without explicitly injecting Auto Capture and CaptureClipboard services. It is not included in this runner. Use the already isolated guide/screenshot exporters for that integration scope, or add deliberate hard-blocked dependency injection in a separate owned wrapper only after review and authorization. No optional render is scheduled or executed by this preparation.
