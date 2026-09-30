# DaBin 0.4.1 — desktop buddy

Version 0.4.1, build 50. Local development candidate; these notes do not claim a public GitHub or TestFlight release.

## Changes

- Larger fitted previews, thin rounded cards, icon actions, and distinct task/completed styles.
- Converting a capture opens its task workspace. Attach files or text by dropping, pasting, or choosing files. Back from an attachment returns to the parent task and its draft.
- Clock reminder editor with date/time and validated hours:minutes countdown. Saving establishes an absolute deadline; reopening or comment edits preserve it.
- Happy robot feedback follows a successfully persisted task completion. Failed saves do not celebrate.
- Library icon filters, responsive columns, and an optional global tooltip preference. VoiceOver names remain available with tooltips off.
- Auto Capture next to the logo, direct Settings gear, and icon-labeled submenus.
- Local application icons and expandable source locations. Native tasks say “Created in DaBin.” External paste destinations are not inferred; website favicons are not fetched.
- Thin robot frame, remembered edge/corner resizing, current-display Expand/Restore, and a 0.55-second manual island reveal.
- A visible flexible header grip moves the compact board without requiring the small logo target; the logo remains draggable too.
- Correct light/dark appearance through the nested native robot frame. Continuous header motion stops when hidden and with Reduce Motion.

## Archive compatibility

Schema 8 adds an optional task parent identifier. Existing schema 1–7 captures remain readable. Attachments retain their own originals, source metadata, capture dates, search/index/export behavior, and backup contents. Removing a task moves its attachment family to Recently Deleted; restoring/deleting families is transactional and recoverable after interruption. Keep a local archive backup before returning to an older app version that does not support schema 8.

## Verification

See [the QA record](qa/buddy-redesign-2026-09-29/README.md) and [independent UX review](design/BUDDY_REDESIGN_REVIEW.md). The local build is ARM64 with a strict code-signature check on a metadata-free copy. App Store signing/notarization and live desktop verification are separate gates.
