# DaBin — Codex application design handoff

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](./OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

## Assignment

Design DaBin as a polished **macOS personal daily board** centered on a tiny metallic purple robot bin. Produce a coherent, reviewable application design and a clickable local prototype. Focus on the user experience and visual system; production capture, persistence, and notification code can come after design approval.

DaBin is a small place to drop or paste things while working, then revisit everything captured on a particular day. It is a personal memory board, with optional comments and reminders on each card. It has **no assignees, required deadlines, completion states, or team task workflow**.

Use the current [product plan](./PRODUCT_PLAN.md) as the product source. The original clickable concept is retained at [references/legacy-first-look.html](./references/legacy-first-look.html) for historical comparison.

That concept establishes the two-window structure and key actions. The first robot prototype is at [design/index.html](./design/index.html), with [design/DESIGN_SPEC.md](./design/DESIGN_SPEC.md) for detailed interaction decisions. An Open Design redesign candidate is at [opendesign-redesign/index.html](./opendesign-redesign/index.html), with its [design notes](./opendesign-redesign/DESIGN_NOTES.md). Review both before selecting the final direction. Do not treat sample data or simplified demo behavior as production requirements.

## Core product model

- A **capture** is created when the user drops or pastes content into the floating panel. It receives an immutable capture timestamp and local calendar day immediately.
- A **card** is the capture's visual representation on that day's board. It keeps a route to the original URL, text, or stored file even if preview generation fails.
- A **comment** is optional personal annotation on a card.
- A **reminder** is an optional future notification attached to a card. It does not move the card away from its capture day or turn it into an assigned task.
- Projects and tags may be suggested quietly later. They are optional metadata and must never block capture or dominate the board.

## Capture types and previews

Design cards for all of these cases:

| Source | Card content |
| --- | --- |
| Pasted or dragged URL | Site/domain, page title, description, thumbnail or image when available, and an open-original action. Show a readable URL card if metadata cannot be retrieved. |
| Image | Thumbnail, name/type, and open-original action. |
| Video | Poster frame when available, name, duration when available, and open-original action. |
| PDF | First-page preview when available, name, page count when available, and open-original action. |
| Document or presentation | Preview if available; otherwise a clear file-type card with the name and open-original action. |
| `.ai` or specialist file | Preview if the system provides one; otherwise a specific file-type or generic file card. Preserve the original. |
| Text or content dragged from an AI app | Render the text, image, link, or file representation that the source actually provides. |
| Unknown draggable content | Show a useful generic card for any readable/transferrable representation. If none is available, give a clear explanation in the capture panel. |

Multiple dropped items create separate cards. Do not make a successful save depend on metadata retrieval, thumbnail creation, tagging, or categorization.

## Required surfaces and states

### 1. Floating robot bin

Design a small metallic purple robot bin that stays convenient while other apps are open. Its separate handle moves it, its body accepts drops, and its small add button opens paste entry. A successful capture triggers a brief digest reaction. Double-clicking the robot body opens Daily; single-clicking opens paste entry without causing an unwanted composer on double-click. Provide keyboard routes to both actions. Show default, drag-hover, paste, saving, success, failure, and compact states. The robot should communicate that links, files, images, video, and text are welcome without becoming a large permanent obstruction.

After a successful capture, the user should know it landed on **today's board** and have a direct way to inspect the new card.

### 2. Daily board

The default view opens on today. It shows visual cards in capture-time order, supports previous/next day and date picking, and works for days with many cards or none.

Place these filters in the Daily board: **All, Links, Files, Media**. They filter only the selected day's cards.

- **Links:** URL cards.
- **Files:** documents, PDFs, `.ai`, and other non-media files.
- **Media:** images and videos.
- **All:** every capture, including text and unknown types.

Show the active filter clearly. Make the empty state specific to the selected day/filter. Search can be included if it stays subordinate to day browsing and the four filters.

### 3. Card detail

Show a larger preview, source/original information, capture time, open-original action, editable comment, and optional reminder date/time. Design how the user clears a reminder and how a long comment appears. The original capture day must remain visible and unchanged.

### 4. Reminders view

Provide a lightweight place to review upcoming reminders with a route back to the original card and its capture day. Keep this secondary to the Daily board.

### 5. Fallback and edge states

Include preview loading/failure, inaccessible link metadata, unsupported drag data, missing source file, long filenames, many simultaneous dropped items, and an empty day. A fallback card should still be useful whenever original content was captured.

## Visual direction

- A calm, clear personal workspace rather than a dense project-management dashboard.
- A crisp, compact purple metal robot silhouette for the floating widget, with restrained motion and a clean macOS Daily board.
- Visual cards that make links, images, videos, and documents recognizable at a glance.
- Capture times easy to scan without overpowering preview content.
- Light and dark appearance, legible contrast, keyboard access, and visible focus states.
- Restrained motion; respect reduced-motion settings.
- Use fictional sample content. Do not include real private project material.

## Deliverables

Put the design work under `DaBin/design/` in this workspace:

1. **Clickable prototype** showing the panel, Daily board, filters, card detail, comments, and reminders with realistic sample content. Make the main interactions work locally in the prototype.
2. **Screen set** covering the required normal, empty, loading, success, and failure states. Screens can be generated from the prototype if clearly named and easy to review.
3. **Design specification** with layout, typography, color, component states, keyboard interactions, and responsive behavior for small and large macOS displays.
4. **Flow notes** explaining capture-to-card, link preview fallback, day navigation, filtering, commenting, and reminders.

Link the entry point and design files in the final handoff response. Explain any intentional deviations from this brief.

## Acceptance checklist

- The design immediately reads as a **daily capture board**.
- A pasted URL visibly becomes a link preview card, with a URL fallback.
- Image, video, PDF, document, `.ai`, and generic file cards have distinct, understandable previews or fallbacks.
- All / Links / Files / Media filters work on the selected date.
- Comments and reminders are optional card actions; neither changes the capture date.
- The robot bin gives clear feedback for save, processing, and unsupported input; double-click opens Daily.
- The interface contains no assignment or completion workflow.
- The prototype is usable without a backend or cloud account and does not upload private data.

## Decisions for the designer to propose

Record a recommendation for each of these in the design specification rather than leaving the interaction undefined:

- Whether the panel follows the user across Spaces and displays, and how a collapsed panel can be found again.
- Whether the Daily filter stays selected when the user changes dates. A newly saved item must remain easy to find even when a filter would hide it.
- How the board labels capture time when the user travels to a different time zone. The original capture day must remain stable.
- When reminder notifications fire, what happens when one is missed, and how a reminder is dismissed or cleared.
- Whether link previews are fetched automatically and how the user can disable network preview retrieval while retaining URL cards.

## Ready-to-send Codex prompt

> Design the DaBin macOS application from `DaBin/CODEX_DESIGN_HANDOFF.md`, `DaBin/PRODUCT_PLAN.md`, and the current `DaBin/design/` prototype. Keep the tiny movable metallic purple robot bin as the capture widget: drop or paste content into it, show a brief digest reaction, and open Daily on a robot-body double-click. Create the requested clickable local prototype, screens, design specification, and flow notes under `DaBin/design/`, and verify the key interactions. Treat DaBin as a personal daily board with rich captured-content cards, All/Links/Files/Media filters, optional comments, and optional reminders. Do not add assignments or task-completion states. Return links to the finished design files and a concise explanation of design choices and remaining implementation questions.
