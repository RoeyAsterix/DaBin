# DaBin — spatial redesign

## Selected design

A small metallic-purple bin stays at the desktop edge. Daily opens inward as one floating panel. Capture, search, detail and reminders replace that panel through separate HTML entrypoints. There is no sidebar, navigation rail, simulated wallpaper, task status, assignee, or project hierarchy.

The supplied robot artwork is retained as identity evidence, while the old panel layout is replaced. The permanent SVG bounds are 32 × 43 px (smaller than the rejected 52 × 64 px robot). Daily is deliberately roomier on demand: reducing the permanent footprint should not also reduce reading comfort.

`concepts.html` compares this with a bottom-docked bin and a horizontal tray. Both comparison windows render at actual CSS-pixel scale. The edge model wins because it leaves the center and Dock area clear. The alternative exposes more captures side by side but has a wider working-area cost and encourages horizontal scrolling.

## Dimensions and visual system

- Rest: 32 × 43 px artwork; 52 × 56 px primary hit area; separate 44 × 18 px move handle. The whole widget wrapper is 58 × 78 px and transparent outside the controls.
- Hover: 39 × 50 px artwork. Drop: transient 84 × 92 px receiver.
- Daily: 420 × up to 640 px; the height shortens with content and viewport. Capture: 400 px wide.
- Bottom alternative: 38 × 36 px artwork; 740 × 322 px tray. Responsive caps prevent the tray exceeding the viewport.
- Shared system: SF Pro Display and SF Pro Text with system fallbacks, SF Mono for capture times. Neutral near-white content surface, graphite type, muted purple actions, status-specific feedback.
- Titles: 23–25 px. Capture names: 16–18 px. Body: 14–16 px. Secondary metadata: 12 px. Desktop icon controls: 36 px; coarse-pointer controls become 44 px where practical.
- Spacing: 4/8/12/16/20 px rhythm. Thin dividers separate captures; no repeated nested cards.
- The first visual capture gets a generous preview. Remaining cards favor scanning. Comment and Reminder remain visible on all cards, including search context.
- Below 600 px the panel fills the available width beside the bin, labels wrap, and redundant Daily navigation is removed from the header. Dark appearance follows the OS; Reduced Motion removes digest animation and transitions.

## Interaction

- Click bin: paste entry after a 480 ms double-click discrimination delay. Double-click: Daily, without opening capture first within this interval.
- Keyboard focus + Enter/Space on the bin: capture immediately. Arrow Down on the bin: Daily. Cmd/Ctrl+Shift+D: Daily. Cmd/Ctrl+K: search. Escape: close the panel.
- Drag the handle to move the bin. Focus the handle and use arrow keys for 5 px steps; Shift+arrow for 25 px. Position stays within viewport bounds when moved.
- Paste text or HTTP(S) URLs; separate lines of URLs produce separate captures. Files can be selected, pasted, or dropped. Multiple files create multiple entries. The browser supplies the readable representations; unreadable drops produce a plain failure message.
- Successful save: short digest motion, confirmation, and a View capture link. Empty input and storage failures remain explicit.
- Local capture date/time/zone are set when saving. Comment and Reminder updates never change them.
- Daily defaults to Today and sorts captures chronologically. Previous/next, date picker, Today, and All/Links/Files/Media filtering work independently of capture date.
- Search matches title, description, original text/URL, comment, kind, and date. Only matching days appear. The immediate same-day item before/after each match is added as context; overlapping context is deduplicated. Type filtering applies to matches, not context.
- Detail provides the original, editable comment, optional reminder date/time, clear reminder, and Save changes. Reminder list links back to the original capture day.

## Data, originals and boundaries

Starter content is fictional. URLs use reserved `.example` domains. The provided SVG studies and text file are real local sample assets; sample video/PDF/Illustrator originals are not included and are explained when Open original is selected.

New text and URL captures use browser localStorage; uploaded originals use IndexedDB. Image previews and video playback use local Blob URLs. This is browser-local prototype storage, not an implementation of native managed file storage or a backup. File inputs and drops never upload content to a service. A file's download action retrieves the stored original.

Live remote link metadata, document first-page generation, native floating windows, account sync, OS notifications, global keyboard shortcuts outside this page, and native drag integration are not implemented. Reminder entries are stored and displayed but do not fire notifications. Preview failure always leaves the captured title/type and original route available where an original exists.

Review query parameters provide repeatable fictional states and keep review metadata separate from the main capture collection. These controls exist only in the review gallery, not inside product UI.

## Native validation still needed

Validate macOS double-click timing and accessibility alternatives, window anchoring across multiple displays, Screen/Space behavior, pointer target discoverability, VoiceOver, non-file drag representations, persistent bookmarks, sandbox permissions, and notification scheduling. Test actual narrow and dark rendering before native implementation.
