# DaBin Dot testing and improvement handoff

Prepared for Roey on 3 October 2026. This is a proposed assignment and access plan. Saving it does not grant permissions, start a Dot task, connect accounts, or schedule recurring work. The assignment becomes operative when Roey gives it to Dot.

Use Dot to coordinate the work and a local Codex task on the connected Mac to build, test, inspect and improve the native application. Code and UI evidence must come from the same verified candidate. The goal is a reliable, easy-to-understand local capture and project app with a playful robot, without adding unnecessary controls.

## Assignment to give Dot

> Take responsibility for one complete DaBin testing and improvement cycle. Read this handoff on my connected Mac at `/Users/roeylibfeld/Documents/KARI Creatives/DaBin/docs/DOT_AGENT_HANDOFF.md` and follow its scope. You may create and coordinate local DaBin Codex tasks, inspect the code, edit DaBin source/tests/docs, build candidates, and run isolated tests without repeatedly asking about routine implementation choices. Coordinate one writer and one build/test runner per checkout, and serialize GUI/focus tests across the whole Mac; use independent review where useful.
>
> First confirm the current source, built, installed and running versions, preserve existing uncommitted work, and establish a fresh baseline. Reproduce and fix important bugs, freezes and usability problems, then repeat the affected real user journeys. Prioritize data integrity and responsiveness, clear capture/search/project/task flows, and enjoyable camera-island behavior. Simplify the UI when it reduces effort. Propose substantial new features or a major visual redesign separately, with evidence of the benefit.
>
> Use fictional data, temporary archives and private test pasteboards. Keep the work scoped to DaBin. Do not inspect KARI material or use my personal captures as test data. Do not push or publish, submit to Apple, contact people, spend money, change security settings, or modify my live archive. Prepare a verified candidate and rollback plan before requesting installation of the app I use every day, unless I separately authorize that installation in advance. Do not force-quit an app with possible unsaved work.
>
> Finish with reproduced issues, fixes, before/after evidence, exact test results and limitations, the candidate's identity, and a short prioritized improvement backlog. Show me what changed using fictional native screenshots or actual animation clips. Report access blockers specifically and continue independent work. Do not call the app tested merely because it compiled or produced attractive screenshots. Keep updates in our Dot conversation. Do not create a recurring schedule unless I request one.

## Establish the current baseline

Repository: `/Users/roeylibfeld/Documents/KARI Creatives/DaBin`.

This is native SwiftUI/AppKit, Core Animation and Core Data, with an ARM64/macOS 14+ target. Use the installed Swift/Xcode tools and repository scripts. This is not the HTML design prototype.

Read-only observation on **3 October 2026 at 19:02 Asia/Jerusalem**:

| Item | Observed state |
| --- | --- |
| Source `native/Resources/Info.plist` | 0.4.26, build 81 |
| `native/build/DaBin.app` | 0.4.25, build 80 |
| `~/Applications/DaBin.app` | 0.4.25, build 80; executable matched the retained build receipt |
| Running process | Not independently established in this audit |
| Registered native suites | 87 at inspection; rediscover with `--list` |
| Latest source-matched report inspected | 4/5 selected suites passed; `HeaderInteractionTests` failed with `Missing accessible control: board-search` |
| Working tree | Extensive modified and untracked work, newer than Git HEAD |

Refresh all these facts at the start. Other tasks may be working on DaBin. Older README version labels and old successful reports are not authority for today's source. The September island preview and locked-session failures are historical; do not assume the Mac is still locked or the same installation blocker persists.

The observed failure is in `native/build/qa/runs/20261003T155912825428Z/`. Determine whether the expected accessible control, navigation state or production implementation is wrong; do not simply weaken the assertion. A reentrant AppKit table warning remains in recent project-view fixtures. It is a lead to investigate, not proof of a freeze or proof that performance is healthy.

Read these sources before deciding what to change:

- Applicable parent/repository `AGENTS.md` instructions.
- `native/README.md`, `native/ARCHITECTURE.md`, `native/CONTRACT.md` and `native/QA_RESULTS.md`; reconcile historical documentation with current source.
- `docs/RELEASE_NOTES_0.4.25.md` and newer release notes, when present.
- `docs/qa/project-workspace-0.4.25-2026-10-03/README.md` for the latest inspected installed project workspace.
- `docs/qa/performance-0.4.23-2026-10-02/verification.json` and `docs/qa/stability-0.4.22-2026-10-02/verification.json` for performance evidence and its limits.
- `docs/qa/testflight-0.4.23-2026-10-03/README.md` for historical GUI failures and distribution blockers. TestFlight is outside this assignment.
- `native/scripts/run_qa.py`, `native/scripts/project_inventory.py`, and the specific production/test files for each issue.

Preserve the working tree before editing. A fresh checkout or default-branch worktree will omit important current work. Use an explicit baseline inventory and, if isolation is needed, a verified local snapshot containing the relevant uncommitted and untracked DaBin files. Do not reset, clean, stash, commit or overwrite unrelated work. Avoid concurrent writers and shared test-cache build collisions.

## Access the owner should enable

Dot's computer connection is separate from a Codex connection or Work Sync. In Dot's profile, use **Computers → Your computer → Allow access**. Keep the Mac online with the ChatGPT desktop app open. Dot can then delegate local work; its cloud computer alone cannot establish physical Mac camera-island behavior. [Official connection guidance](https://learn.chatgpt.com/docs/dots/computers-and-apps).

| Access | Recommended scope and reason |
| --- | --- |
| Local files | Read/write the DaBin repository, its local build/evidence folders and task-owned temporary fixtures. Include scoped tool caches when a build actually needs them. |
| Local commands | Git inspection, Swift/Xcode compilation, Python/shell repository scripts, local rendering, test execution and diagnostic reads. No blanket administrator access. |
| Computer Use | Enable the Computer Use plugin and approve DaBin and named QA hosts. Approve Finder or a test destination app only for specific drag/drop, reveal or paste journeys. |
| macOS permissions for the Computer Use helper | Screen Recording for visual inspection and Accessibility for clicking, typing and navigation. These permissions belong to the automation helper, not DaBin. |
| Synthetic test data | Create/edit local fixtures, import/export through chosen fixture folders, and exercise recoverable removal/restore using fixture records. Use a dedicated test screenshot folder. |
| Internet | Public documentation and justified development dependencies as needed. Core fixture tests should work without internet. Optional website-preview tests require an explicitly chosen public URL. |
| Everyday app replacement | Separate scoped permission for `~/Applications/DaBin.app` and `~/Applications/.DaBinBackups/`, after a tested candidate, normal quit and rollback plan. Local test hosts do not require replacing the everyday app. |
| GitHub | Optional for repository/issue/PR work. It is unnecessary for local QA. Separately authorize remote writes and limit access to the DaBin repository if requested. |

Enable and review app access under the desktop app's Computer Use settings. macOS system permissions and individual app approvals are separate from file/shell permissions. [Official Computer Use setup](https://learn.chatgpt.com/docs/computer-use).

For the first desktop run, arrange an unlocked, logged-in session. Optional Locked Use is a separate owner decision; do not turn it on, change sleep/security settings, or attempt to bypass a lock automatically. If GUI access is unavailable, continue source/isolated checks and leave GUI verification explicitly pending.

DaBin itself does **not** need Full Disk Access, Accessibility, Screen Recording, camera or microphone access for its current core behavior. Its screenshot channel watches a user-selected folder; it does not record the display. Selected import/export folders and optional reminder notifications are distinct app permissions. Mock notifications first; ask the owner to handle any real OS permission prompt needed for end-to-end testing. See `native/Resources/DaBin.entitlements` and the native guide.

Optional custom rules can permit routine DaBin edits and tests while reserving live installation, external publication and private-data changes for review. Rules do not grant missing computer/plugin access or override required confirmations. Configure them under **Settings → Personalization → Custom rules** if desired. [Official Dot controls](https://learn.chatgpt.com/docs/dots/controls).

No email, calendar, Slack, broad cloud-drive connection, Apple credentials, signing-key access or paid inference API is needed for the first testing cycle.

## Isolate tests from personal data

The normal application opens its real archive. At inspection there is **no supported full-app `--qa-root` argument or environment variable**. Do not invent one, override the home directory, or launch the normal app assuming it has been isolated. `--organize-archive` is a real maintenance operation, not a test mode.

Existing fixtures use `CaptureStore(root:)`, temporary `UserDefaults` suites, injected notification clients and private named `NSPasteboard`s. `ApplicationCoordinator` supports store/defaults/client injection. Prefer these facilities and existing native test hosts. `native/scripts/build_drop_qa.sh` builds a separate drop QA application; inspect its fixture setup before use. If a whole-app journey needs better isolation, add a dedicated test-only host using these injection points, with a distinct identity and explicit temporary paths. Keep diagnostic hooks out of distribution builds.

The live archive normally resides at `~/Library/Containers/com.dabin.mac/Data/Library/Application Support/DaBin/`. It is excluded from fixture data, screenshots, uploads, cleanup and stress tests. Do not delete the database to recover from an error. Preserve capture originals, receipt dates, notes, tasks, reminders, projects and unsaved edits.

The parent workspace contains private KARI intellectual property. Do not traverse or use `project_sources/KARI_VISUAL_CANON/`, screenplay files, ComfyUI installations or unrelated project folders. A connected Mac does not make cloud-coordinated reasoning an offline system; limit inspected content and UI captures to DaBin source and fictional fixtures.

## Test the user journeys

| Area | Required observations |
| --- | --- |
| First use and navigation | Empty state explains how to save and find something. Core destinations and Back behavior are discoverable; keyboard shortcuts focus the correct control. Measure steps and hesitation points. |
| Capture | Text, links, images, regular files and supported file promises; clipboard/screenshot opt-ins, pause/resume, burst counts, project destination, duplicates and errors. Preserve original bytes. |
| Search | Global search from every route; project/type/source/date intersections, all dates, no results, DOCX/PDF/text/OCR matching, Back and draft preservation. |
| Projects | Preview-first grid/compact views, live notes, selection, filters, assignment, task conversion, ordering, complete project copy/export and reopen persistence. |
| Tasks and follow-ups | New task, priority/tags, reminders, recurring behavior, timer expiry/acknowledgement, completion/undo and unsaved form content. |
| Recovery | Recoverable removal, Undo, backup and restore round trips on synthetic archives; conflicts, missing files and interrupted operations. Real permanent deletion is outside scope. |
| Windows and input | Compact/expanded/narrow layouts, resize grips, monitor movement, display reconnection, focus, tab order, paste/drop destinations, tooltips and accessible labels. |
| Robot and island | Physical contact with the island, readable animation, capture eating/counts, project recording sign, timer priority, click/drop area, interruption, open/close/reversal, external-display fallback and Quiet/Reduce Motion. |
| Performance | Growing archives, scrolling while capture/previews/OCR arrive, large images/documents, repeated open/close/resize and a bounded sustained run. Record main-thread stalls, CPU/memory, fixture size and duration. |

Use the real production renderer and native views. Evaluate visual clarity, target size, clipped content, unnecessary controls and motion enjoyment separately from functional correctness. Preserve the recognizable character unless the owner approves a broader redesign.

Some DaBin panels exclude capture and have returned blank screenshots even when accessibility worked. A blank image is not proof of appearance or a rendering defect. Use fictional native render fixtures for visual evidence and report live visual limits; do not disable production privacy protections to obtain a picture.

## Commands and execution order

From the repository root, inspect the scripts and inventory before executing:

```sh
cd '/Users/roeylibfeld/Documents/KARI Creatives/DaBin'
git status --short
python3 native/scripts/run_qa.py --list
python3 native/scripts/run_qa.py --only HeaderInteractionTests
```

Record the baseline and reproduction. Then work in small changes, run affected suites, and replay the relevant native journey. Once inputs are stable, complete broader validation:

```sh
python3 native/scripts/run_qa.py
./native/scripts/test_media_integration.sh
./native/scripts/render_qa.sh
DABIN_SIGNING_IDENTITY=- python3 native/scripts/build_app.py
git diff --check
```

Use `--storage-only` when live focus is unavailable, labeling it partial coverage. It runs non-focus suites, not an entirely headless workload; some still need macOS AppKit/pasteboard services. Do not use keyboard-skipping switches to claim complete keyboard QA. Regenerate the Xcode project with `python3 native/scripts/generate_project.py` when source inventory changes. Run the existing unsigned Xcode Release build and packaging checks when relevant to the change; signed distribution is a separate task.

Run one build/test pipeline at a time in a checkout, and only one GUI/focus run at a time across the whole Mac. Worktrees still share AppKit focus; the drop QA script also shares fixed app/result paths under `/private/tmp`. The explicit signing value above keeps local builds ad-hoc and avoids using an inherited distribution-signing identity. Avoid source/resource/test/script edits during fingerprinted runs. Keep compiler and runtime failures, including failed attempts. A sandbox denial, locked Mac, missing app approval, flaky timing, stale assertion and production defect are different diagnoses; gather evidence before classifying them. Never lower assertions or timing limits just to obtain green output.

Use the repository's guarded installer only after installation is authorized:

```sh
python3 native/scripts/install_app.py
```

Check unsaved work, quit normally, preserve the previous bundle and any appropriate archive backup, install, verify signatures/version/executable and source hashes, and inspect that exact installed build. Do not bypass the running-app guard. Stop for permission if a force-quit or unapproved live-data operation becomes necessary.

## Completion and reporting

Save each cycle under a new dated `docs/qa/dot-<date>-<cycle>/` folder. Retain the baseline identity, source diff, exact commands, per-suite results, logs, native screenshots/videos, build receipt, measurements and remaining limitations. If native output already has a report path, link it rather than inventing a success receipt.

For each issue record severity, steps, expected/actual behavior, fixture/environment, evidence, root cause, fix and regression coverage. Distinguish a reproducible bug from a usability hypothesis. For significant UI work compare action counts or task completion time before/after; do not claim improved market demand without user or market evidence.

A cycle is complete when the selected problems are fixed and retested, the required regression coverage matches unchanged candidate inputs, relevant native journeys are verified, a reviewable build and rollback plan exist, and unresolved access/product decisions are explicit. Count test suites and user journeys honestly; thousands of pixel/choreography assertions are not thousands of separate user scenarios.

Return a concise owner report: what improved, what remains, pass/fail/blocked totals, actual artifact links, installed versus candidate status, and up to three prioritized next improvements with user benefit, evidence, effort and UI cost. Give routine progress in the Dot conversation and interrupt for a concrete blocker or decision. Any recurring cadence or external notification destination requires a separate explicit instruction.
