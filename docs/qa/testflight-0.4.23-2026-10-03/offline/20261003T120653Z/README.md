# Offline TestFlight preparation audit — pre-fix

Candidate: **DaBin 0.4.23 (78)**. This evidence is local structural/tooling verification, not distribution readiness, upload processing or beta-review acceptance. No signing, keychain/account access, upload, native GUI testing, personal archive or clipboard use occurred.

## Results

- 45/45 metadata/distribution Python tests passed; no skips, 0.041 seconds.
- 32/32 Store preflight/builder Python tests passed; no skips, 0.003 seconds.
- 30/30 static source-packaging checks passed, including deterministic generated-project/source inventory.
- 13/13 draft metadata checks passed; `submissionReady` remains false.
- Strict public-release metadata validation failed the expected 12 unresolved owner/external gates. This is **not a TestFlight-specific validator**: price, territories and public-release choices must not be treated as beta-review requirements solely because they appear in this local checklist. The review-contact fields are also unset locally; authoritative current beta information must be resolved separately.
- A separate disposable archive-path probe **failed**: a nonexistent component followed by `..` can make an accepted archive destination resolve inside the prohibited source tree. No archive was created. The ordinary literal external destination passed. File Provider attribute probing was mocked so the test isolates path containment.

Twenty relevant scripts, test/configuration files, project files and metadata inputs were byte-identical before/after these commands; see `inputs-before.sha256` and `inputs-after.sha256`. This inventory is not a complete native-runtime receipt.

## Exact commands

Run from the DaBin repository root. All commands used the bundled runtime below with `-B` to avoid generating bytecode beside source files. Standard output/error were retained in this directory using the filenames noted here.

```sh
task_python=/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3

# python-tests.log — exit 0
"$task_python" -B -m unittest discover -s native/Tests -p 'test_*.py' -v

# store-preflight-tests.log — exit 0
"$task_python" -B native/scripts/test_app_store_preflight.py

# static-preflight.log — exit 0
"$task_python" -B native/scripts/app_store_preflight.py --static-only

# metadata-validation.json — exit 0
"$task_python" -B native/scripts/validate_app_store_metadata.py

# metadata-strict-readiness.json — expected exit 1
"$task_python" -B native/scripts/validate_app_store_metadata.py --require-complete

# archive-location-audit.json — exit 1, confirmed guard defect
"$task_python" -B docs/qa/testflight-0.4.23-2026-10-03/offline/20261003T120653Z/archive-location-audit.py
```

## Packaging audit boundary

The archive helper does not enable provisioning downloads, export or upload. Store preflight checks distinguish a development archive from a final Store-signed app, and reject a direct GitHub updater payload. Static checks do not execute those signed-app gates. The metadata validator always returns `submissionReady: false` and checks draft copy/version constraints, not an App Store Connect account or beta submission state.

The archive-path fix has not been applied in this receipt. Its script is part of `build_inventory()`, so applying that fix changes the embedded build fingerprint and requires rebuilding a Store candidate. It is not part of the native Swift QA runner's source snapshot. Subsequent fix/testing evidence must be kept separately from these pre-fix results.
