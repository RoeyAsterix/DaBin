Projects functionality audit — DaBin 0.4.33 (88)

Automated Projects goals pass on source fingerprint 41b3f117c76dc5f22051c7be2833caecd6cfd4e00345dc4f99f60c8c998820fc. The full registered campaign initially passed 120/123 suites. Scoped rechecks corrected an obsolete persistence expectation and the native window harness; the consolidated result is 122/123 passing on identical 137 production source files, resources and scripts. Only the two recorded test inputs changed after the full run. The final window test reaches its explicit completion and cleanup marker; an earlier exit0 without that marker is retained as incomplete evidence.

Confirmed failures were fixed:

- Project/Unfiled selection and Back/Forward save the entire workspace scope before publishing a new destination. Failed writes retain the prior scope and history; retry remains possible. Removal keeps successful trash while returning coherently if workspace restoration fails.
- Browsing pickers reject blocked or late-blocked selections/creation; independent metadata filing remains available.
- Named projects expose Undo move. Failed Undo writes retain retryable receipts; later edits invalidate Undo. Task conversion Undo protects pending task/comment edits and disappears when it cannot safely act.
- Snippet naming retains the typed draft and inline error after failure, with a visible retry. Successful save or deliberate Cancel closes the form.
- Compact layouts expose every type through a labeled menu, keep Grid/List visible, and recover empty filtered results through one Show all items action.
- Boundary reorder actions disable; filtering and sorting prevent inappropriate manual reorder. Selection anchors are cleared when the selected item disappears.

The 14 goal groups in action-coverage.json map creation/browsing, history/drafts, import/move, notes, selection/filtering/reordering, original opening, copy/export, tasks, snippets, removal, search, recording and graphics to their suites. Native controls, real More/filter menu dispatch, private clipboard payloads, original ZIP bytes, store failures and restart recovery are exercised. Live native Menu hosts retain their intrinsic AppKit dimensions inside the padded SwiftUI layout; the tests verify their actual enabled, visible target and action rather than assuming their AX cell has the layout container's height.

The duplicate-action review preserves distinct goals: whole-project versus selected export/copy; saved captures versus live project notes; local details versus original-file opening. Direct actions also available through More, and Project notes also available through Notes mode, remain useful entry points. Impossible/stale Undo and boundary reorder actions were hidden or disabled. No working functionality was removed merely for offering an alternate entry point.

Durability passed 8,586 checks including 1,000 seeded records, 320 mixed operations, 25 restart comparisons, backup/restore and 4 SIGKILL boundaries. Flow/action stress passed 11,674 checks across 12 routes. Seeded graphics/animation passed 109,041 checks. The strict 30-second zoom test still fails: input-to-layout p95 62.884ms against 50ms, and steady run-loop p95 70.973ms against 33ms. Gates and workload were preserved. Native framework table warnings remain open. This is not an all-findings-fixed claim or a ten-minute soak.

Seven curated fictional renders retain source/run/hash provenance. Narrow Projects controls and reset results are visible without overlap; wide cards preserve receipt metadata. Native sheet PNGs preserve transparency, so preview compositing alone does not establish native button contrast. Naming/retry/Cancel interactions were verified separately. The narrow filter PNG shows the All/Any date reset result; the actual empty-reset button is covered by native activation.

Unsigned arm64 App Store Release compilation and packaging pass; actual embedded source/version/build and binary SHA match the receipt. The initial compile succeeded but packaging rejected missing new test references in the generated Xcode inventory. Regeneration added only those references and its group membership; the rebuilt candidate passed. Signing, sandbox runtime, installation, an archive and Apple upload remain unverified.

Manual coverage still includes user operation of Finder/system file panels, physical trackpad/mouse/IME, human VoiceOver usability, longer soak and hardware/OS combinations, and installed distribution behavior. Project rename and removal of project markers are not implemented; no broken control for those actions is claimed fixed. Disposable fictional archives, isolated preferences, private pasteboards and injected external openers protect production data. The unrelated local-update QA folder was preserved.

Reports retain initial failures, corrected rechecks, the incomplete zero-exit attempt, packaging failure and current successful compile. verification.json consolidates the accepted results. Next validation priorities are investigating the measured zoom hot paths without weakening the budgets, then performing the listed physical/system-panel checks on the signed build.
