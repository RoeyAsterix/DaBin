# DaBin — Codex design and UX handoff

Prepared 30 September 2026 from the current Open Design project, after the task-card, content-trail, project-picker and responsive refinements.

**Implement this design in the existing native DaBin application.** The HTML is an interactive reference for SwiftUI/AppKit implementation, not a replacement application architecture.

## Use this package

1. Extract the ZIP beside your working DaBin repository. Keep its folder structure intact.
2. Open Codex in the working repository, attach or point it to this extracted folder, and paste [CODEX_PROMPT.md](CODEX_PROMPT.md).
3. Codex should read [DESIGN_UX_HANDOFF.md](DESIGN_UX_HANDOFF.md), review the prototype, then implement in the working repository. The included `source/native/` is a frozen reference, not the active checkout.

No new discovery questionnaire or visual-direction selection is needed. The selected design is already represented in the files.

## Review the design

Serve this folder with `python3 -m http.server 4178 --bind 127.0.0.1` and open `http://127.0.0.1:4178/index.html`. If that port is occupied, choose a free one. Keep all screens on the same origin so project context, drafts and fixture data persist.

Start with [Robot](robot.html), [Inbox](inbox.html), [Today](today.html), [Workspace](workspace.html) and [Task detail](task-detail.html?id=review). `index.html` is a review launcher, not product UI.

Review sequence: capture → direct task icon → card changes in place → set hours/minutes → start/pause → schedule → switch/create a project → inspect source/destination logos. These screens contain fictional review data.

## Read in this order

| File | Purpose |
|---|---|
| `CODEX_PROMPT.md` | Copyable implementation assignment |
| `DESIGN_UX_HANDOFF.md` | Current design, UX contracts, native mapping, migration plan |
| `ACCEPTANCE_CHECKLIST.md` | Implementation acceptance and release gates |
| `HANDOFF_QA.md` | Checks performed on this delivery and known gaps |
| `open-design-v3/DESIGN.md` | Detailed design system |
| `open-design-v3/FEATURES.csv` | All 80 feature-preservation rows |
| `open-design-v3/specs/FEATURE_CONTRACTS.md` | Detailed existing feature contracts |
| `open-design-v3/specs/ROBOT_MOTION.md` | Robot choreography and accessibility behavior |
| `source/` | Original brief, reference screens, native source and tests |
| `PACKAGE_MANIFEST.json` | SHA-256 inventory for this delivery |

The handoff documents resolve older notes explicitly. Historical QA totals describe earlier iterations; use `HANDOFF_QA.md` for the current result. Original reference screenshots show build 53 or labeled historical build 50, not rendered images of this redesign.

## Edit and rebuild the reference

Edit shared files in `open-design-v3/`, then run from this folder:

```sh
python3 open-design-v3/build.py
python3 open-design-v3/verify.py
```

The verifier requires macOS JavaScriptCore. Its 361 passing checks cover code, fixture behavior, markup and geometry functions; they do not prove rendered browser layouts or native integration. Native implementation, visual review and accessibility validation remain required.

The 19 root product HTML files are generated outputs. Do not patch only one of them: the next rebuild would overwrite the change. The existing `source/MANIFEST.json` belongs to the frozen source snapshot; `PACKAGE_MANIFEST.json` covers this complete handoff.

Optional transfer-integrity check: run `python3 verify_package.py` before editing. It compares files with the delivered manifest; intentionally changed files will be reported as changed.
