# Synthetic build 86 → pinned current build data upgrade

Prepared on 2026-10-06. The first build 97 attempt compiled both harnesses and
wrote the old fixture, then failed the QA temporary-root string guard before
the current archive read. That actual failure and its inputs/logs are preserved
under `prior-attempt-97/`; the original run remains unchanged. The repaired guard
uses canonical path components, private ownership/permissions and a runner-token
marker. **Execution is blocked pending the parent's new production/module freeze.**
Preparation is not a test pass. Run only after the parent releases the native
build slot; compilation/execution is sequential and headless.

```sh
python3 docs/qa/testflight-upgrade-0.4.42-97-2026-10-06/run_upgrade_fixture.py --run
```

The runner rehashes the preserved uploaded build 86 candidate inputs, both cached
Release Store core source inventories and module outputs, and the current build
source freeze before every phase. Its version/build/module identity comes from
the explicitly pinned `prepared-inputs.json`; optional `--current-version`,
`--current-build` and `--current-module-cache` arguments must match that pin.
It compiles only two small fixture executables
against those already-built cores. It does not compile or launch the application,
sign/archive/export, contact TestFlight, or use a user's archive or clipboard.
All fictional storage, temporary files and logs stay in a newly owned mode 0700
`/private/tmp/DaBin-Upgrade-*` directory, with explicit archive URLs and private
CFFIXED_USER_HOME/TMPDIR. HOME and CODEX_HOME are preserved. Fixture
execution additionally denies network access using the macOS sandbox.

The exact historical production CaptureStore writes four real schema 10 records:
a note with whitespace/Unicode and supplied provenance, a task with planning,
checklist/order/reminder and a multiline legacy aggregate comment, an imported
file attached to that task, and an automatic receipt with its action ID. Its
WorkspaceStore writes project color/scratchpad/shelf/order/selection; its
DraftArchive writes uncommitted note/task/detail drafts. The expected manifest
comes from these actual old-core records rather than synthesized legacy JSON.

The current production reader checks every old-emitted field (with the schema
version treated separately), original-file SHA256, capture counts and immutable
IDs, workspace/drafts, legacy comment recovery and local search. Its real save
writes schema 11. Two subsequent independent current-reader processes check
preservation again. A preserved old-archive backup and a separate downgrade copy
are retained; the old repository must reject the new schema with its specific
unsupported-metadata message. **Downgrade to build 86 after current saves is
unsupported.** Do not uninstall/reset the tester's container or delete its data
when updating through TestFlight.

Expected output: the printed absolute `report.json` path, `status: passed`, each
phase/result passed, schema 10 → 11, unchanged original SHA256 and capture IDs,
and `downgradeSupportedAfterCurrentSave: false`. The receipt records commands,
timestamps, exit codes, source/module/executable hashes and logs. A source change,
failed compile, denied sandbox launch, failed check or timeout remains a failure.
No native process has been run merely by preparing this directory.

Preferences are qualified static evidence only: AutoCaptureSettings is byte
identical between the exact old source and current source, and the optional
website-preview Boolean key is unchanged. No real preferences or preference
domains are read or altered. These checks do not prove a physical TestFlight
replacement, a distribution-signed app runtime, every possible existing store,
or Apple processing/approval. `submissionReady` remains false in this fixture's
receipt because those are outside its scope.
