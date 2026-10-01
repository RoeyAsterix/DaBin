# Selected robot: Quiet Orbit around the island

This is the latest direction after the user's requests for a friendly cool robot, no rings, smaller size, quieter behavior, funny automatic capture and movement around the entire island.

## Character and material

Use `editable/robot-concepts/orbit-character.svg` as the editable part geometry. It is an SVG **fragment**, not a standalone image. `orbit.svg` is the complete composed reference scene; `preview/robot-orbit.html` is authoritative for posed states and motion.

The robot has a chamfered metallic-purple head and body, dark inset visor, two square illuminated eyes, a small digital smile, a short neck, articulated shoulders/elbows, segmented fingers and a physical intake slot. Purple/silver gradients describe metal only. Keep the silhouette mechanical; friendliness comes from expression, gesture and timing. No hoops, halos, tether ring, blush, floating hands or organic creature face.

Material gradient stops are preserved in the builder and scene SVG: purple metal `#eee7f4 → #c8b4dc → #977cad → #bca5d0 → #6d5387`; edge `#e9dff1 → #b59dc8 → #6d5387`; silver `#f6f4f8 → #d4cddc → #a9a1b3 → #e3dce9 → #85758f`; visor `#3e3449 → #1e1924 → #30253b`. Reuse the precise fills and seams in the asset, not a loosely similar emoji or raster mascot.

The page palette is ancillary preview chrome: almost-white canvas, purple action, quiet neutral text. The product scope is the robot, not this review page.

## Size and hardware relationship

- Reference scene: `viewBox="0 0 400 270"`.
- Reference camera: x=128…272, y=0…34, rounded lower corners. It is painted after the character as a fully opaque mask.
- Character transform: `translate(128 -10) scale(.36)`. This is the current size, approximately 31% smaller than the superseded `.52` version.
- The reference head is roughly 36 design units wide versus the 144-unit housing. Use the supplied complete geometry to judge size; this is not an absolute native pixel specification.
- Keep a usable interaction area independent of the tiny artwork. Preview target is up to 320 × 120 CSS px; that entire rectangle must **not** become an opaque event-blocking native panel.
- Top corners mean drawable pixels adjacent to the camera housing. There is no route above the physical top of the display. Hardware is never replaced with a fake display for facial features.

## Seven perches

Coordinates below are assembly offsets in the reference SVG space, with y increasing downward. They are not AppKit global screen coordinates. Position relative to the measured hardware; translate coordinate systems explicitly.

| Perch | Visible x,y | Hidden x,y |
| --- | --- | --- |
| upper-left | −89, −7 | −48, −22 |
| left | −89, 5 | −48, −15 |
| lower-left | −62, 23 | −38, −22 |
| bottom | 0, 23 | 0, −25 |
| lower-right | 62, 23 | 38, −22 |
| right | 89, 5 | 48, −15 |
| upper-right | 89, −7 | 48, −22 |

Left-side poses mirror the inner facing group via `translateX(400px) scaleX(-1)`. Mirror only the character, not screen placement or hardware. The inside hand stays attached to the edge; the outside hand performs the catch/wave. Preserve arm continuity.

Pointer mapping in the demo uses center-relative x and top-relative y: |x|<35 chooses bottom; otherwise y<22 chooses the upper corner, y>38 with |x|<80 chooses a lower corner, and the rest chooses a side. These are reference thresholds to normalize to real hardware. A 150 ms dwell precedes changing a visible perch; the latest requested destination wins during the hidden transition.

## Interaction and timing

| Trigger | Response | Reference timing |
| --- | --- | --- |
| Initial preview | Brief bottom peek, then tuck away | 1,800 ms hold |
| Approach/focus | Reveal at approached perch | 480 ms assembly transition |
| Leave | Grace, retreat, idle | 420 ms grace; 440 ms state settle |
| Change perch | Hide behind housing, relocate, wink | 320 ms hide CSS; 550 ms relocation; 1,000 ms expression |
| Tap / explicit greeting | One small wave or wink | 1,400 ms state; 1,300 ms wave |
| Gentle tug | Bounded displacement, release with nod | 6 px threshold; ±8 x, −2…12 y; ±5° lean in source coordinates |
| Manual drop | Reach/intake, then confirmation | 800 ms intake + 1,400 ms reaction |
| Auto saved receipt | Peek → gulp → quiet comic response | 500 + 700 + 1,300 ms |

No continuously running idle animation. No periodic sound, big bounce, patrol or presentation loop. Perch rotation is tied to approach, deliberate input or a confirmed unattended capture. An active catch does not chase the pointer.

Auto response rotation: `auto-proud` (small belly pat/nod), `auto-hiccup` (tiny head hitch/O mouth), `auto-sneak` (small double take/wink). The browser sample runner waits 12 seconds **after** each 2.5-second routine, with a 450 ms first-start delay. Those are demonstration timings, not a native polling interval. Production should coalesce bursts and avoid a performance for every clipboard update; keep the robot quiet while capture continues reliably.

## State and interruption contract

Browser states: idle, peek, ready, catching, reacting, hiding, waving, winking, peekaboo, petting, cuddling; automatic states auto-peek, auto-gulp, auto-proud, auto-hiccup, auto-sneak.

Native lifecycle ownership stays authoritative. Display/shutdown handling and open-app actions override decoration. Manual capture interrupts automatic/playful motion. Extra manual drops queue as one counted follow-up; confirmed auto events defer behind manual work. Never interrupt a held drag with decoration. Cancel stale timers and release captured pointers after interruption. Off cancels automatic decoration but does not cancel an active manual save.

Successful feedback comes from native save completion, not the preview's timeout. Errors keep their native status and retry route; no success smile/badge for a failed save. Hidden/closed preview resets are only browser lifecycle demonstrations, not a rule to discard native saved receipts.

## Reduced motion and accessibility

Use a short opacity change (120–180 ms) with static expression/confirmation. Remove travel, rotation, file flight and body tugging. Retain all capture/open actions and readable success/error feedback. Keyboard focus is visible, but hovering or an auto receipt must not take focus. Keep names and outcomes accessible; do not repeatedly announce idle expressions. Preserve native keyboard commands over the demo's optional arrow navigation.

## Review surface only

The sample file, Catch / Say hi / Peek around buttons, reset, automatic-event switch, explanatory captions and simulated desktop are review tools. Do not ship them as new native product controls. Bind existing preferences and commands instead. The browser preview rejects folders for simplicity; native supported drop types must remain unchanged.
