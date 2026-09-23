# DaBin — native macOS app handoff

Prepared 22 September 2026 from the selected Open Design v2 prototype.

**Build a real native macOS app: a tiny movable purple capture bin and one readable floating panel, with no sidebar.** The HTML is the design and interaction reference. It is not the app runtime.

## Use this package

1. Extract this folder somewhere Codex can read.
2. Open the destination app repository in Codex. Inspect it before writing and preserve any existing work.
3. Paste [CODEX_PROMPT.md](CODEX_PROMPT.md) into Codex. It points to the reading order and implementation milestones.
4. Review the running native app against [ACCEPTANCE.md](implementation/ACCEPTANCE.md). Do not accept screenshots alone as proof of working capture or persistence.

No app code, Xcode project, compiled `.app`, signing or notarization is delivered in this package. Those are Codex's next task.

## Read in this order

| File | Purpose |
| --- | --- |
| [Codex prompt](CODEX_PROMPT.md) | Ready-to-paste implementation assignment |
| [Product and design](implementation/PRODUCT_AND_DESIGN.md) | Locked behavior, screen contract, dimensions and native UX decisions |
| [Native build](implementation/NATIVE_BUILD.md) | Architecture, capture, managed originals, previews and reminders |
| [Acceptance](implementation/ACCEPTANCE.md) | Milestones, automated cases and hands-on native checks |
| [Source map](implementation/SOURCE_MAP.md) | Precedence, provenance and official API references |
| [Design tokens](implementation/design-tokens.json) | Extracted light/dark values plus native sRGB conversion |
| [Search fixtures](implementation/search-cases.json) | Deterministic contextual-search examples |

## See the design

- [Daily](reference/prototype/daily.html)
- [Resting bin](reference/prototype/rest.html)
- [Capture](reference/prototype/capture.html)
- [Search](reference/prototype/search.html)
- [Capture detail](reference/prototype/detail.html)
- [Reminders](reference/prototype/reminders.html)
- [21 review states](reference/prototype/review/index.html)
- [Concept comparison](reference/prototype/concepts.html): the edge model is selected; the bottom tray is a comparison only.

Serve `reference/prototype/` over a local HTTP origin when exercising browser storage. If Python 3 is available, run `python3 -m http.server 8765 --bind 127.0.0.1 --directory reference/prototype` from this folder, then open `http://127.0.0.1:8765/daily.html`. The prototype is fictional fixture data and has known limitations; a packaged copy starts with its own browser-origin storage.

## Scope and decisions

- Preserve the selected design and the explicit **no-sidebar** constraint.
- Recommended implementation default: SwiftUI content hosted in AppKit panels; macOS 14+; local SwiftData metadata and managed attachment files. These are proposed engineering defaults, not facts about an existing app.
- Ship capture, Daily, contextual search, detail, comments, reminders, real previews/fallbacks and durable originals.
- Use a small menu-bar menu for recovery and Quit. Link-preview privacy belongs in compact native settings, not a navigation sidebar.
- The prototype has 14 recorded logic/DOM-neutral checks. Its rendered layout and actual browser interactions were not verified. There is no completed native QA. [Original QA notes](reference/prototype/QA_NOTES.md) preserve the exact boundary.
- `PACKAGE_CHECKS.json` reports handoff packaging checks only. `MANIFEST.sha256` covers the delivered files; it does not certify app behavior.

The package preserves the selected prototype and robot asset byte-for-byte. Do not treat old handoff requests to explore a new design as a new assignment: that design phase already produced v2.
