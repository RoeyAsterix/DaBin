# DaBin 0.3.11

## A livelier robot at the camera island

Successful Auto Capture now feels like the robot lives behind the Mac camera island. It first peeks toward the new capture, springs smoothly into view, celebrates, then slips back with a soft finish. The complete sequence takes about two seconds and starts only after DaBin has safely stored the capture.

DaBin rotates through twelve distinct reactions: a wink, victory dance, double bounce, camera flash, card catch, clipboard hug, dizzy spin, wobbly salute, Saved stamp, confetti sneeze, screen high-five and a quick sneak-and-grab. A shuffled rotation prevents any of the previous three reactions from repeating, while small changes in gaze, timing and entrance keep later appearances lively.

## Calm during capture bursts

- Rapid captures reuse one click-through robot instead of stacking popups.
- The current move finishes once while a compact `×N` badge updates immediately.
- One saved action uses the robot's checkmark and does not show a redundant `×1`.
- Failed or partly failed actions stay on the error path and never play a celebration.

## Native placement and accessibility

On a built-in primary display, DaBin uses macOS's real camera-island geometry and attaches the transparent animation panel to its lower edge. An external primary display uses the safe top-right area. The popup never accepts clicks, takes focus, changes Spaces or appears in screenshots.

With **Reduce Motion** enabled, the full celebration becomes a short static peek, success checkmark and gentle fade. DaBin reads the setting for each new burst. The feature has no sound.

## Data compatibility

This update changes only native presentation and animation. Existing captures, tasks, comments, reminders, preferences and archive folders require no migration.

## Verification

Deterministic tests cover the twelve-reaction shuffled rotation, previous-three exclusion, bounded variation, complete 1.8–2.6 second timelines, Reduce Motion phases, camera-island/external placement, rapid-count reuse, focus safety, capture exclusion, cancellation and cleanup. Native render QA covers the celebration library against light and dark backgrounds.
