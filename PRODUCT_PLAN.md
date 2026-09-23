# DaBin — personal daily board

## The idea

DaBin is a hidden macOS companion for things you worked with. Move the cursor into any screen corner and a little metallic purple robot peeks inward. Drop or explicitly paste directly into the robot; each item becomes a visual card on the day you added it. Browse a date to remember the links, images, documents, files, and thoughts that passed through your day.

**Product promise:** “Drop it now. See your day later.”

DaBin is a personal record, not an assignment system. There are no assignees, required deadlines, or task statuses. A comment or reminder is optional for any item.

## First version

The first version is a macOS app with two surfaces:

1. **Corner robot:** completely hidden at rest, with no persistent widget, badge, handle, drop zone, or background. Entering any of the four screen corners with the cursor reveals the metallic purple robot peeking inward. The robot itself is the only capture target: drop onto its body, or focus it and use an explicit paste command. There is no separate paste area, composer, text box, or add button. After saving a capture, it performs a brief digest animation. Leaving the corner retracts it once any active drag, paste, or digest interaction finishes safely. Double-clicking the robot opens the Daily board.
2. **Daily board:** a compact, content-sized surface that opens on today, with no side menu, desktop backdrop, or decorative outer background. Each captured item appears in capture-time order and has visible **Comment** and **Reminder** buttons. Date arrows and a calendar picker move between days. An **All / Links / Files / Media** filter narrows the current day's cards. Search groups matches by capture date with their immediate context.

**Interaction assumption for the redesign:** an explicitly opened Daily board remains interactable until dismissed. Moving the cursor away from the corner to use the board must not close it. The hidden-at-rest rule applies to the resting capture widget; it does not prevent an intentionally opened board from remaining available.

The item's board date is the local date when it entered DaBin. Adding a reminder later does not move the item to a different day. Reminders appear on the original card and can also be viewed in a dedicated reminder list later.

## Capture and card types

| Input | Daily card |
| --- | --- |
| Link | Page title, site name/domain, description, image when available, and the original URL. If preview retrieval fails, keep a readable URL card. |
| Image | Thumbnail, filename or short title, format, and an open action. |
| Video | Poster frame or thumbnail when available, filename, duration when known, and an open action. |
| PDF | First-page thumbnail when available, filename, page count when known, and an open action. |
| Document or presentation | Quick Look preview when available; otherwise a file-type icon, filename, and open action. |
| `.ai` or other specialist file | Quick Look preview if macOS provides one; otherwise a file-type card with the original file intact. |
| Text or content from an AI app | Text excerpt or the image/link/file representation actually provided by the source app. |
| Unknown draggable item | Preserve the usable data representation and show a generic card. If the source provides no readable or transferable data, explain that clearly beside the revealed robot. |

Multiple dropped items create separate cards. Pasting a URL creates a link card, not a plain text note. DaBin should never claim it captured data that the source app did not expose through drag or paste.

## Core flow

1. With DaBin hidden, the user moves the cursor or drags content into any screen corner. The robot peeks into view and stays reachable as the pointer moves onto it.
2. The user drops an item directly onto the robot, or focuses the robot and explicitly pastes. Hover alone never reads or saves the clipboard.
3. DaBin saves the original URL, text, or file and the capture time immediately, then performs a short digest animation to confirm success. A failed save must not show the success reaction.
4. DaBin builds a preview in the background. If this fails, the original item remains accessible. The robot retracts after the pointer leaves and the current interaction safely finishes.
5. A double-click opens the Daily board. Every card offers Comment and Reminder buttons; both actions are optional.
6. The user returns to any day to scan its cards, open original content, or search across dates. Dismissing the board restores the hidden resting state when the cursor is outside a corner.

## Required contextual search

Search results show only the capture dates containing a match, in a compact calendar Daily view with no decorative outer background. Each result includes the matching paste plus the immediately preceding and following capture from that same day, when available. Never pull context from an adjacent day. Merge overlapping context windows so each card appears once per date; distinguish matches from context without adding large containers. Keep Comment and Reminder available on every shown card.

Search across saved titles, original text or URLs, descriptions, source names, and comments. If a type filter is active, apply it to matches; the immediate neighboring captures still provide context even when they have a different type. Clearing search returns to the selected day's ordinary Daily view. Optional OCR or other future enrichment is not required for the initial search experience.

## MVP scope

| Priority | Capability | Completion rule |
| --- | --- | --- |
| P0 | Hidden corner access | No visible resting widget. Cursor or drag entry into any of the four screen corners reveals the robot, with a reachable transition onto its body and safe retraction after exit. |
| P0 | Direct robot capture | Links, text, images, PDFs, documents, and arbitrary files dropped or explicitly pasted into the robot become durable cards. Multi-item drops work. No separate capture area, composer, text box, or add button. |
| P0 | Digest feedback | A brief robot animation confirms a successfully saved capture; reduced-motion feedback communicates the same state. |
| P0 | Visual Daily board | Cards appear under their original local capture date, with useful previews or a clear fallback. |
| P0 | Daily type filters | All, Links, Files, and Media show only matching cards for the selected day. Files includes documents, PDFs, `.ai`, and other files; Media includes images and videos. |
| P0 | Link previews | A pasted or dragged URL resolves to a card with title, domain, description, and image when available; preview failure retains the URL. |
| P0 | Comments | Every card has a Comment button and can hold an optional editable personal comment. |
| P0 | Reminders | Every card has a Reminder button and can have an optional reminder date/time, separate from its capture date. |
| P0 | Reliable originals | Opening a card can reach its original URL or locally stored file after the app restarts. |
| P0 | Contextual date search | Show only dates containing matches; show each match with one capture before and after it from the same day, deduplicating overlaps. |
| P1 | Optional organization | Suggest a project or tags when useful; let the user correct or ignore them. The board works without organizing anything. |
| Later | More context | Richer previews, OCR, source-app details, and smarter local categorization. |

## Screen states

- **Hidden:** the app has no visible desktop presence until the cursor reaches a corner.
- **Corner peek:** the purple metal robot peeks inward from the active corner. Its body is reachable for drop, focus, paste, and double-click.
- **Drag hover:** the robot accepts the content directly; its intake or expression responds without revealing a separate drop area.
- **Saved / digest:** a short, small animation confirms successful capture. Reduced motion uses a brief static expression change or status indication.
- **Retraction:** after cursor exit, finish any active capture feedback and then hide. Avoid disappearing while the user moves from the corner onto the robot.
- **Daily board:** compact visual cards with timestamp, preview, Comment and Reminder buttons, and All / Links / Files / Media filters; no sidebar or desktop background.
- **Search:** only matching dates, each with matching captures and the immediate same-day capture before and after; no decorative background.
- **Card detail:** large preview, open original, add/edit comment, and set/clear reminder.
- **Preview fallback:** original item remains usable even when metadata or thumbnail extraction fails.

## Data model

`Capture`: stable ID, immutable capture timestamp in UTC, time-zone ID and local capture date, source representation/type, original URL/text or managed attachment path, preview title/description/image/thumbnail path, optional source app, optional comment, optional reminder timestamp, optional project and tags, preview status, created/updated timestamps.

Store the original data separately from generated preview data. A failed preview can be retried without risking the capture. Project and tags are optional metadata, not required filing steps.

## Design and implementation decisions

- **Platform:** macOS first, with cursor and drag detection at all four screen corners. A single-click can focus the revealed robot for explicit paste; it must not open a composer. A double-click opens Daily. Provide a keyboard route to focus the same robot and open Daily for accessibility.
- **Presence:** no persistent floating widget or visible corner markers. The robot is revealed by intentional corner access and retracts safely after the interaction. The opened Daily board remains available until dismissed.
- **Storage:** local first. Copy dropped files into DaBin-managed storage so cards remain valid if the originals move. Keep the original file names and types.
- **Calendar meaning:** the Daily board is capture history. A reminder is an optional notification about a specific card.
- **Privacy:** no account or cloud processing in the first version. Link preview retrieval may contact the linked website; the app should make that behavior clear and allow previews to be disabled.

## What to validate in the mockup

1. Is the desktop completely clear at rest, and can the robot be reached reliably at every corner while moving or dragging?
2. Can someone tell at a glance what they worked with on a given day?
3. Do link and file cards feel useful even before any project label is added?
4. Can a comment or reminder be added quickly, without turning a card into an assigned task?
5. Does a direct drop or explicit paste produce clear digest feedback without opening another capture surface?
6. Do search results show only matching dates, with exactly the available same-day neighbors and no duplicate cards?

## Reference status

[OPEN_DESIGN_HANDOFF.md](./OPEN_DESIGN_HANDOFF.md) is the authoritative redesign brief. The included `opendesign-redesign/`, `design/`, and `references/` material records rejected historical design directions. Use it to understand behavior and prior feedback; its visible resting robot, capture composers, dimensions, or layouts do not override this corrected product model. Create the new design separately in `DaBin/open-design-v2/`.

## First implementation milestone

Build hidden corner access, direct robot capture, durable storage, link previews, and the compact Daily board with contextual search. A usable build should pass this scenario: reveal the robot from each corner; drop an image, a PDF, and an `.ai` file directly onto it; explicitly paste a link into it; observe digest feedback and safe retraction; double-click to open Daily; add a comment and reminder to one card; search for a capture and inspect its date and immediate neighbors; quit and relaunch; navigate back to that day; and open every original item.
