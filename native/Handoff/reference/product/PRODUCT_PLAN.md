# DaBin — personal daily board

## The idea

DaBin is an always available place to drop or paste something you worked with. Each item becomes a visual card on the day you added it. Browse a date to remember the links, images, documents, files, and thoughts that passed through your day.

**Product promise:** “Drop it now. See your day later.”

DaBin is a personal record, not an assignment system. There are no assignees, required deadlines, or task statuses. A comment or reminder is optional for any item.

## First version

The first version is a macOS app with two surfaces:

1. **Floating robot bin:** a small metallic purple robot that stays available while working. Drag its handle to move it; drop content onto its body or paste through its small add button. It briefly digests a successful capture. Double-clicking the robot opens the Daily board.
2. **Daily board:** a larger window that opens on today. Each captured item appears as a visual card in capture-time order. Date arrows and a calendar picker move between days. An **All / Links / Files / Media** filter narrows the current day's cards.

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
| Unknown draggable item | Preserve the usable data representation and show a generic card. If the source provides no readable or transferable data, explain that clearly in the panel. |

Multiple dropped items create separate cards. Pasting a URL creates a link card, not a plain text note. DaBin should never claim it captured data that the source app did not expose through drag or paste.

## Core flow

1. User drops or pastes an item into the robot bin.
2. DaBin saves the original URL, text, or file and the capture time immediately, then gives a short digest reaction and confirms it was added to today's board.
3. DaBin builds a preview in the background. If this fails, the original item remains accessible.
4. User may add a short comment or set a reminder on that card. Both are optional.
5. User returns to any day to scan its cards, open the original content, or search across the board.

## MVP scope

| Priority | Capability | Completion rule |
| --- | --- | --- |
| P0 | Drag and paste capture | Links, text, images, PDFs, documents, and arbitrary files become durable cards. Multi-item drops work. |
| P0 | Visual Daily board | Cards appear under their original local capture date, with useful previews or a clear fallback. |
| P0 | Daily type filters | All, Links, Files, and Media show only matching cards for the selected day. Files includes documents, PDFs, `.ai`, and other files; Media includes images and videos. |
| P0 | Link previews | A pasted or dragged URL resolves to a card with title, domain, description, and image when available; preview failure retains the URL. |
| P0 | Comments | Any card can hold an optional editable personal comment. |
| P0 | Reminders | Any card can have an optional reminder date/time, separate from its capture date. |
| P0 | Reliable originals | Opening a card can reach its original URL or locally stored file after the app restarts. |
| P1 | Search | Find items by words, date, and optional labels. |
| P1 | Optional organization | Suggest a project or tags when useful; let the user correct or ignore them. The board works without organizing anything. |
| Later | More context | Richer previews, OCR, source-app details, and smarter local categorization. |

## Screen states

- **Idle robot:** a small purple metal bin with expressive eyes, visible move handle, intake lid, add button, and today's capture count. A compact form takes even less space.
- **Drag hover:** the lid opens and a short hint confirms the target accepts the content.
- **Saved:** brief confirmation with a way to open today's card.
- **Daily board:** visual cards with timestamp, preview, optional comment/reminder indicators, and All / Links / Files / Media filters.
- **Card detail:** large preview, open original, add/edit comment, and set/clear reminder.
- **Preview fallback:** original item remains usable even when metadata or thumbnail extraction fails.

## Data model

`Capture`: stable ID, immutable capture timestamp in UTC, time-zone ID and local capture date, source representation/type, original URL/text or managed attachment path, preview title/description/image/thumbnail path, optional source app, optional comment, optional reminder timestamp, optional project and tags, preview status, created/updated timestamps.

Store the original data separately from generated preview data. A failed preview can be retried without risking the capture. Project and tags are optional metadata, not required filing steps.

## Prototype decisions

- **Platform:** macOS first, matching the requested always available desktop drop target. A single-click opens paste entry; a double-click on the robot opens Daily, with a keyboard route to both.
- **Storage:** local first. Copy dropped files into DaBin-managed storage so cards remain valid if the originals move. Keep the original file names and types.
- **Calendar meaning:** the Daily board is capture history. A reminder is an optional notification about a specific card.
- **Privacy:** no account or cloud processing in the first version. Link preview retrieval may contact the linked website; the app should make that behavior clear and allow previews to be disabled.

## What to validate in the mockup

1. Does the movable robot bin stay convenient without covering too much of the desktop?
2. Can someone tell at a glance what they worked with on a given day?
3. Do link and file cards feel useful even before any project label is added?
4. Can a comment or reminder be added quickly, without turning a card into an assigned task?

## First implementation milestone

Build the panel, durable capture storage, link previews, and Daily board first. A usable build should pass this scenario: drop an image, a PDF, and an `.ai` file; paste a link; add a comment and reminder to one card; quit and relaunch; navigate back to that day; and open every original item.
