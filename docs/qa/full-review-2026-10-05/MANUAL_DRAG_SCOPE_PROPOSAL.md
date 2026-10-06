# Isolated manual-drag staging scope

The original proposal was recorded at `2026-10-05T21:27:22.105533Z`. The coordinator subsequently authorized implementation. **Implemented and offline-tested** at `2026-10-05T21:32:10.391412Z`: [13 synthetic receipt-gate regressions passed](manual-drag-scope-verification.json). The strict full-pass default and performance thresholds remain unchanged. No real fixture was prepared, signed or launched.

There is a legitimate distinction between permission to prepare an isolated diagnostic fixture and a passing release campaign. A failed performance gate does not invalidate a current, verified drag fixture binary or make its fictional data unsafe. It does prevent a full-QA/release-pass claim. The existing full-passing-report default should remain intact.

The stager now accepts explicit `--scope manual-fixture-only` and repeatable `--report` arguments. The receipt uses `scope: manual-fixture-only`. Its enforced rules are:

1. Require the coordinator's exact current frozen production fingerprint, Release channel/compile definitions, module receipt and output hashes, current manual-fixture source hash and cached executable hash; verify them again after staging. Retain the current unique app/bundle identity, fictional temporary data, no-service/manual branch and no-launch behavior.
2. Preserve the supplied QA reports exactly, including their `status: failed`, failures, original UTC intervals, test hashes and `coverage` values. Never edit a report to pass, drop a failing suite or change performance thresholds. Record the performance failure as unresolved, with its original report/hash link.
3. Require the current `NativeContentDragTests` result and all **explicitly selected functional checks for this diagnostic scope** to pass with matching current test inputs. A full run with only `WorkspaceZoomPerformanceTests` failing can meet that condition. A selected functional rerun can support only its listed checks, not a claim that all application functionality passed. `not_requested`, compilation failure, timeout, crash and skipped checks must not count as passing.
4. If combining an original failure receipt and a corrected functional rerun, verify the same frozen production module and retain both test-source hashes. Derive each input snapshot from its actual requested suite set. A changed test invalidates its older assertion result; it must have a new current-hash PASS. Do not compare a selected-suite report with the full-suite snapshot or combine different production candidates into one alleged passing run.
5. Permit only the explicitly retained performance-budget failure as an unresolved acceptance gate for this scope. The suite must have compiled successfully, exited 1 and reported the existing 50 ms or 33 ms budget assertion; an unrelated assertion/crash/timeout is rejected. Any unresolved functional failure blocks the stated “selected functional checks passed” condition. The staging receipt states `scope: manual-fixture-only`, `overallQAStatus: failed`, `releaseAcceptance: false`, lists every required/passed/unrequested check and failure receipt, and says `applicationLaunched: false`.
6. Keep preparation and actual GUI interaction separate. After native GUI QA is released, preparation may copy and ad-hoc sign only fresh owned fixture outputs. Opening the exact fixture and interacting with fresh local destinations remains a separate coordinator action. No production archive/preferences, general clipboard reads, AutoCapture, notifications, network or existing unrelated receiver process should be introduced.

Candidate 4's first run is **ineligible**: it passed 5/7 and failed both `ProjectWorkspaceViewTests` and `WorkspaceZoomPerformanceTests`. Its next corrected-query attempt also failed a live-note accessibility lookup. Neither failure can be waived by this scope. The coordinator subsequently locked a new production fingerprint with a bounded displayed-excerpt accessibility fix; qualifying current-hash reports for that source are still pending. Do not infer a functional PASS from an explanation or source fix.

All supplied receipts must match current requested inputs and one identical compiler/SDK/target/distribution module configuration. Do not supply obsolete failed functional receipts as qualifying evidence; retain them in the campaign history separately. A later passing receipt cannot silently supersede a failing functional receipt included in the same staging request. The default `--scope full-pass` requires exactly one full passing report and does not merge partial results.

After the coordinator provides final current receipts, the verification-only command shape is:

```sh
python3 -B docs/qa/full-review-2026-10-05/stage_manual_drag.py \
  --scope manual-fixture-only \
  --report "$DABIN_CURRENT_FUNCTIONAL_QA_REPORT" \
  --report "$DABIN_CURRENT_PERFORMANCE_QA_REPORT" \
  --expected-source-fingerprint d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa
```

Alternatively supply one current full report whose only failure is the specified performance-budget assertion. Add `--prepare` only after coordinated GUI QA releases the stage. The stager never launches. The above is not evidence that suitable reports or a successful preparation already exist.

Even after such a scoped fixture passes an actual TextEdit/browser/Finder drag, its result covers the observed production gesture and basic fictional writers. It does not certify the archive-backed `ExplorerTransfer` exporter, App Sandbox grants, final signed installation, browser upload service, performance gate or full release readiness.
