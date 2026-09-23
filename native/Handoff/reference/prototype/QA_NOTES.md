# QA — DaBin v2

## Verified locally

- JavaScript syntax check passed for `app.js` and `model.js`.
- Local HTTP server returned 200 for the Daily entrypoint.
- Fourteen model and DOM-neutral smoke checks passed. Full results: `review/qa-results.json`; repeatable check source: project-root `tools/qa_dabin.cjs`.
- Type grouping covers URLs, images, videos, PDF, Illustrator, common documents and unknown files, including common media with missing MIME types.
- Search tests cover one hit, multiple matching days, same-day boundaries, context deduplication and different-type neighbors under an active filter.
- Comment/reminder edits preserve capture ID, date, timestamp and timezone.
- Screen initialization and save handlers were exercised in a DOM-neutral harness, including multiple URLs, empty input, comments and reminders.
- Optional WebMCP tools registered in a mock context; representative valid inputs and invalid inputs were checked against the same application functions.

## Static acceptance review

- Separate HTML entrypoints exist for every primary product surface.
- No sidebar, assignees, task completion states or required deadline.
- Visible Comment and Reminder links on all capture cards.
- Capture and reminder dates remain distinct.
- Link/file/media fallback paths remain readable without successful preview extraction.
- Native storage, metadata and notification features are not presented as complete.
- OS appearance and Reduced Motion rules exist; keyboard focus, labeled controls and local navigation routes are implemented.
- The 21-state gallery and both concept frames show live product surfaces without designer controls inside the product.

## Outstanding verification

The installed Open Design screenshot wrapper rejected the requested screenshot command as unsupported. Per the supplied one-render-attempt limit, no fallback browser was launched. **No rendered screenshots or real-browser interaction tests were completed.** The review gallery contains live HTML states, not PNG evidence. Layout, contrast in rendered states, file-dialog/drop behavior, click/double-click timing, keyboard traversal, and dark/narrow appearance therefore remain unverified in a real browser.

WebMCP was tested with a mock registry only; no supported browser WebMCP validation context was available.

Native macOS window behavior and notifications are outside this browser prototype. The design is ready for local review, with the above QA gap still open.
