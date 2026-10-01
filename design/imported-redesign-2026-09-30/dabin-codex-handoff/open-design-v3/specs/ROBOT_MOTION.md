# DaBin robot motion contract

Native ownership: RobotLifecycle, RobotMotion, IslandRobotChoreography, RobotAppFrameView, AutoCaptureRobotPresenter, AutoCaptureRobotCelebration. Preserve their generation token and cancellation ownership; do not replace them with independent timers. The browser study in robot.html is labeled simulation.

## Geometry and interaction

Content minimum 380 × 430 pt. Reserved frame: 10 pt each side, 32 pt above, 18 pt below; minimum outer 400 × 480 pt. Also review 400 × 730 outer / 380 × 680 content and 780 × 730 outer / 760 × 680 content. Do not stretch a raster into a Retina claim.

The lid, face, hands and feet lie outside the content rectangle. Only the outer 6 pt resize rail is interactive. Decoration ignores hit testing. The header empty region moves the native panel; double-click expand restores the remembered compact rectangle. Compact content scrolls internally; headers remain bounded. During filtering the top edge is anchored, the bottom eases over 160 ms, and both endpoints clamp to the visible safe area. Reduce Motion changes height immediately. No resize clears route, selection, query, project, drafts or scroll.

Hidden rest has no continuous animation work and no permanent drop panel. Hover/drag in the configured corner or compatible island reveals a stable target; external/no-island fallback is top-right. Open on the interacted display. Display removal cancels intermediate geometry and clamps to a connected display's safe area. Never switch Spaces. Native capture exclusion remains requested; macOS recording APIs vary and protection must not be described as universal.

## State graph

Hidden → revealing → peek/ready → saving → saved reaction → retreat → hidden.

Any stable or transitional state + Open → opening → open. Opening wins over capture and consumes/cancels its presentation generation without canceling the underlying save. Open + Close → closing → hidden. Quit cancels the animation generation, persists recoverable drafts and shuts services down immediately. A failed save goes to a readable error, never a saved token. Retry preserves input and destination.

| Transition | Duration | Layers and easing | Stable interruption endpoint |
|---|---:|---|---|
| Hidden → eyes → climb/peek | 550 ms | opacity 0→1; transform from safe edge; cubic (.2,.75,.25,1) | Open wins; retreat otherwise returns hidden |
| Robot torso → app | 1150 ms | torso halves transform outward; content reveal mask expands at final layout size; head rises to reserved rail; arms/feet settle | open, with content focus after geometry settles |
| App → robot → hidden | 420 ms | reverse torso transform and mask; content remains mounted until completion | hidden; a new Open reverses to open |
| Saved generic token + reaction | 1800–2600 ms | transform and opacity only; never captured text/image | hidden or open according to newest intent |
| Task completed | 650 ms movement, 1100 ms smile | head +2/−1/+1/0 pt; eyelid scale 1/.2/1 | open; no new window |
| Reduce Motion | 140 ms | opacity fade, static count/checkmark; no travel or squash | same logical endpoint |
| Quiet | ≤140 ms visual confirmation | no reaction travel; no sound | same logical endpoint |

Gaze is clamped inside the eye display and eased toward the pointer; it never shifts panel geometry. Visibility changes suspend hidden blink and gaze loops. No reaction requests focus or plays sound.

## Ten distinct saved reactions

All begin with a persisted successful action and a generic token. A bounded queue aggregates follow-up actions into an exact count. Only one presenter may exist. Shuffle the eligible rotation, excluding the preceding three reactions. Counts represent saved actions, not file members or attempted saves. Cross-channel image dedup happens before counting.

| Reaction | Duration | Distinct motion | Quiet / reduced |
|---|---:|---|---|
| Quick Bite and Satisfied Blink | 1800 ms | token drops 60 pt; small lid snap; single slow blink | static count + blink |
| Oversized Bite and Recoil | 2100 ms | token scale 1.3; head tilts −9° then +5°; body retreats 8 pt | static count |
| Capture Noodle Slurp | 2300 ms | token stretches vertically then contracts toward intake; two short head pulls | short opacity dissolve |
| Nibble the Corners | 2400 ms | four token corner masks disappear sequentially; alternating ±5° head tilt | static token → check |
| Toss and Mouth Catch | 2200 ms | token arcs 32 pt upward; head tracks bounded arc; catches at intake | static count |
| Oversized Swallow | 2300 ms | torso scale 1.12/.94 then .98/1.04; no content-layer deformation | static count |
| Chase the Escaping Capture | 2600 ms | token moves ±16 pt; robot follows with lag; bounded to safe presentation area | static count |
| Suspicious Inspection | 2400 ms | head −12° pause 300 ms; eyes narrow; token accepted after inspection | still narrowed eyes → check |
| Stacked Capture Snack | 2500 ms | generic tiles feed in sequence; count remains exact even for aggregated burst | count only |
| Digital Hiccups | 2100 ms | three ±3 pt impulses; small square token echoes dissolve; no sound | static count |

The browser study animates distinguishable body keyframes for all ten with a selected count. Native token masks, body-to-window choreography, no-focus guarantees, notch/corner placement, display changes and screenshot exclusion remain implementation verification gates.

## Native acceptance sequences

1. Save, then Open halfway through token motion: one app, no orphan robot; captured record exists once.
2. Close during opening, then Open: resolve to final Open intent, restore route and focus; no invisible capture window.
3. Three same-hour auto captures stay individual; fourth creates summary. Invalid saves and deduplicated images do not increase count.
4. Rapid successful captures while reacting: one bounded follow-up aggregate, exact count, no private contents in decoration.
5. Unplug interacted display while peeking: one safe top-right fallback; no off-screen window.
6. With Reduce Motion, Quiet, Reduce Transparency and Increase Contrast: every intake and action remains available.
