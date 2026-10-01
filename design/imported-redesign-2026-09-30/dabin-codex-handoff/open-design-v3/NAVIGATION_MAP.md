# Old → new navigation and interaction review

The chosen system keeps existing labels and adds Activity as a peer destination. No permanent sidebar. All screens retain the source robot identity and native geometry contract.

| Build 53 entry | Redesigned entry | Change |
|---|---|---|
| Inbox primary tab | Inbox primary tab | Preview-led cards, one composer, progressive card actions |
| Today primary tab | Today primary tab | Workday first; separate Upcoming and Completed |
| Workspace primary tab | Workspace primary tab | Shared project selector and four named collections |
| Inbox Activity / More | Activity primary tab | One click from any main destination |
| Daily / Weekly | Activity Day / Week | Stable centered date group and scope-specific search/export |
| Add icon | Header + menu | Four named actions retained |
| Auto icon and footer setup | Status next to logo + Settings | Explicit off/on/paused/error vocabulary |
| Detail work-plan accordion | Task detail two-pane expanded / stacked compact | Original capture stays alongside plan |
| Settings gear | Settings gear | Direct access preserved; no intermediate menu |
| More → Trash | Settings → Recently Deleted | Removal toast provides immediate Undo |

## Alternatives considered at actual CSS size

1. **Labeled top navigation — selected.** One click between the four primary places. Predictable position in compact and expanded views. Two bounded chrome rows preserve discoverability without a sidebar.
2. **Destination switcher.** Saves a row at minimum height. Switching destinations requires open + choose (two clicks) and hides the product structure. Keep as a future option only if actual user observation warrants it.
3. **Bottom destination dock.** Familiar touch model but farther from desktop capture/search controls and competes with status/footer. Rejected for this macOS-first product.

The design-review page displays the two compact header alternatives at 380 CSS px. This is an expert design comparison, not user research or a timed study.

## Interaction counts — predicted from source/control paths

Text entry, file selection and OS permission actions are reported separately; these are expert path counts, not measured user task times.

| Same task | Build 53 path | New path | New click count |
|---|---|---|---:|
| Quick text capture | Inbox composer → submit | Inbox composer → Capture | 1 after text entry |
| Convert capture to task | Detail/card conversion | Actions → Turn into task | 2 from card |
| Open global search | Header search / ⌘K | Header search / ⌘K | 1 / keyboard |
| Copy a capture | Upper-right copy | Upper-right copy | 1 |
| Switch existing project | Project menu → selection | Project selector → selection | 2 |
| Add reminder from task | Detail → clock → Save | Reminder → choose → Save | 2 plus date entry |
| Export selected day | Day scope menu → export | Export → Export text file | 2 plus native save panel |
| Open Settings | Gear | Gear | 1 |
| Move between core places | Primary tabs or Activity link | Labeled primary tab | 1 |

No empirical before/after performance improvement is claimed. Reassess with the same fixture, window size and input device after native implementation.
