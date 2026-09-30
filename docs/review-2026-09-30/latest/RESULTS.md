# Current review evidence

## Native flows observed through CUA

The corrected live fixture was opened through Finder, then selected by its separate bundle ID. These wrapper checks did not operate on the installed DaBin or its archive; production installation checks are reported separately in the main review. Tests below ran against module `c65504a672c105cb5b94e097511ef0ceb75bdabbb9b13c0a5a763cbe093db03a`; the final layout below is verified separately against the final source module.

- **Quick note:** one Inbox field click, typing, Return. The note appears at the top, the composer clears and “Note saved to Inbox” appears. Baseline creation needed three button actions and typing.
- **Promote capture:** one conversion action opens the same record as a task with its original text retained.
- **Plan Today:** Plan Today, Save changes, Today tab. The task appears in Today's plan. The previously selected Launch project correctly hid this unfiled task until All projects was selected; project scope is visible above the list.
- **Scratchpad:** typed text in Workspace Notes, switched to Inbox and back. Text remains with a saved status. Quit and relaunched through Finder; Notes mode and the exact text are restored. The task receipt also retains convertedToTask and its planned day in the saved synthetic capture JSON.
- **Search return:** Library → Media → global search “launch” → Back restores Media with the same single image. The baseline filter-loss bug no longer reproduces.
- **Hide/reopen:** Hide then fixture Show restores the Workspace route and Media filter. This uses the review wrapper callback, not the production notch animation.
- **Quit:** Command-Q terminates the isolated app. The event log records quit; the wrapper check terminated only its own process.

These are real native accessibility actions, not just screenshots. Click counts exclude typing, automation retries and the two menu actions used to change the existing project filter. CUA occasionally reported a stale element after a successful navigation; refreshed native state verified the outcome. `live-1790747407183-reminders-400x700.png` was captured by the fixture while the corresponding live Today view was open.

An initial wrapper launch failed because its preference-suite name matched its bundle ID. The wrapper now uses a separate `.preferences` suite and handles failure with an error. This was a test harness defect, not a production app crash. The CUA launch call also waited 792 seconds before reporting the failure; that tool delay is excluded from performance measurements.

## Layout findings and fix

Thirty-six native view renders cover Inbox, Today and four Workspace modes, two appearances, 380 × 430 minimum content, 380 × 680 compact content and 760 × 680 expanded content. The first version passed ordinary-size inspection but failed usefulness at the minimum:

- Library left only a card title visible.
- Shelf's fixed toolbar consumed the remaining list area.
- Notes actions were below the initial viewport. Notes already had an outer scroller, so the actions remained reachable by scrolling; this was poor discoverability, not data loss.

Evidence is preserved under `before-compact-fix/`. The fix combines mode icons and labels on one horizontal row, merges type and extra filters, moves the count into the project row, scrolls the Shelf toolbar with its cards, and moves Notes actions above the editor. Final render verification passed against module `b5942dd2565c206ad19945c5b2c849a71432e993ed3e6bdf1c5de91e06135b11`: the minimum Library displays a complete first task card, Notes actions are initially visible, and Shelf items share the toolbar’s scrollable area. See `final-render-verification.json` for image hashes and the representative views inspected. A Shelf card still requires scrolling at the minimum height; controls remain available. Expanded mixed-height grid cards now align at the top. Missing source icons use the capture-kind symbol while retaining an honest accessible “source unavailable” description. The final five representative renders were visually rechecked after both changes.

## Performance

The 10,000-record runs use generated text, one batch metadata save, production search and a temporary archive. Both runs use optimized production QA modules. They are single local runs, partly concurrent with other QA; no statistical product-wide speed claim is implied.

| Operation | Baseline | Current | Interpretation |
| --- | ---: | ---: | --- |
| One batch metadata save, 10,000 records | 319,633 ms | 719 ms | Approximately 445× faster for this specific batch path after eliminating repeated pending-record fetches. |
| Search, 100 matches / 10,000 text records, median of 12 runs | 127.2 ms | 125.4 ms | Similar search cost; this optimization targets loading and saving. |
| Search maximum across those 12 runs | 155.6 ms | 141.1 ms | Local sample only. |
| Metadata-ready load, readable folder repair deferred | Not measured separately | 1,139 ms | New foreground startup data path. |
| Warm metadata-ready load | Not measured separately | 1,081 ms | Same synthetic archive after readable mirrors exist. |
| First eager readable-folder generation plus load | 60,993 ms | 108,242 ms | Heavy file creation; current measurement is maintenance, not foreground startup. Concurrent filesystem load makes these poor comparison numbers. |

The live fixture measured **551 ms and 1,407 ms** on two launches, from delegate construction through setup and synchronous first layout for the small seeded archive. Reopening the existing window measured **108 ms**. These exclude process bootstrap, GPU presentation and the production robot-window transition; they must not be labeled full app launch time.

Four idle samples over nine seconds in the visible Workspace Media view report **0.0% CPU**, **147,072 KiB RSS** (about **143.6 MiB**) and unchanged cumulative CPU time of 2.50 seconds. As with the baseline, this is a short local observation, not a power benchmark. See `idle-samples.json`.

Raw JSON: `performance-10k.json`, `review-events.json`; frozen raw baseline: `../baseline/performance-10k.json`. The first baseline JSON labels its aggregate load as archiveLoadMS; it includes generating readable mirrors. The current JSON explicitly separates metadata-ready, warm and first-mirror timing.
