# Offline TestFlight preparation audit — post-fix

Candidate: **DaBin 0.4.23 (78)**. This receipt follows the separately preserved [pre-fix audit](../20261003T120653Z/README.md). It is not a distribution-ready, upload or beta-review acceptance claim.

## Guard correction

`native/scripts/app_store_archive_location.py` now rejects a `..` path component before ancestor, source-tree and File Provider checks. This closes the confirmed case where a nonexistent directory before `..` concealed the eventual source-tree destination. Ordinary external destinations and filenames containing embedded dots remain valid. A new dedicated `native/Tests/test_app_store_archive_location.py` verifies eight cases using disposable directories and mocked File Provider attribute inspection.

The original isolated path probe was rerun unchanged against the fixed guard: **PASS**. The formerly accepted traversal is refused, an ordinary external destination is accepted, and no archive is created.

## Results

- **53/53** discoverable offline Python tests passed: the prior 45 metadata/distribution tests plus eight archive-location tests. Zero failures or skips, 0.047 seconds.
- **32/32** independent Store preflight/builder tests passed. Zero failures or skips, 0.003 seconds.
- **30/30** static source-packaging checks passed.
- **13/13** draft metadata checks passed; `submissionReady` remains false.
- Strict public-release metadata validation still fails the expected **12** unresolved owner/external gates. This validator is not specific to TestFlight; it does not determine which beta-review fields are required or inspect App Store Connect.
- All **21** bound source/test/configuration inputs were identical before/after the post-fix commands. Hashes are in `inputs-before.sha256` and `inputs-after.sha256`.

No native GUI tests, signing, keychain/account access, upload, network, personal archive or clipboard operations were performed by this audit. Existing evidence was preserved in the separate pre-fix directory.

## Build and QA inventory impact

The packaging script is a production build-inventory input because `build_inventory()` includes `native/scripts/*.py`:

- Before: `a1693632a2a03ba795d64db3f4b26036b8739f6284d616ab7d786baa63fd9570`.
- After: `f8f78939bb00cb20f49877d3d477840d6ed964168cc2a0fc19ae43ab3dc2d140`.

The script change therefore changes the embedded source fingerprint and requires a new Store candidate. It does not change Swift production source or the native QA runner's `input_snapshot()`/module inputs. The new Python test is outside both the production build inventory and the native Swift QA snapshot. The exact post-fix Store build/signature/runtime evidence must be recorded separately; passing these offline checks does not validate the prior build as current.

## Exact commands

Run from the DaBin repository root. Output was retained in this directory under the indicated filenames.

```sh
task_python=/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3

# python-tests.log — exit 0; includes eight new archive-path regressions
"$task_python" -B -m unittest discover -s native/Tests -p 'test_*.py' -v

# store-preflight-tests.log — exit 0
"$task_python" -B native/scripts/test_app_store_preflight.py

# static-preflight.log — exit 0
"$task_python" -B native/scripts/app_store_preflight.py --static-only

# metadata-validation.json — exit 0
"$task_python" -B native/scripts/validate_app_store_metadata.py

# metadata-strict-readiness.json — expected exit 1
"$task_python" -B native/scripts/validate_app_store_metadata.py --require-complete

# archive-location-audit.json — exit 0 after guard correction
"$task_python" -B docs/qa/testflight-0.4.23-2026-10-03/offline/20261003T120653Z/archive-location-audit.py
```
