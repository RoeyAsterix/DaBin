# DaBin 0.3.12

## Search the part of a week you need

Weekly now gives Search an explicit scope menu:

- Choose any date in the displayed seven-day range, then use **Search Day**.
- Use **Search Week** to search all seven calendar dates together.
- The chosen content filter still limits matches, and each result keeps its immediate same-day action before and after for context.
- Back returns to the Weekly range you were browsing.

The day picker includes all seven dates, even when an empty date has no visible Weekly column.

## Copy or download one day or the complete week

Weekly's export action now offers four choices:

1. **Copy Day**
2. **Download Day**
3. **Copy Week**
4. **Download Week**

Day output is named `DaBin-YYYY-MM-DD.txt`. Week output is named `DaBin-Week-YYYY-MM-DD-to-YYYY-MM-DD.txt`. Each copy/download pair uses exactly the same deterministic UTF-8 text, sorted chronologically. Downloads include every recorded action in the chosen calendar scope and ignore the active content filter. Image-only actions retain their type and timestamp and use their caption, OCR text or a clear placeholder.

The controls disable empty scopes, explain when there is nothing to export, report success or failure for the chosen scope, close with Escape or an outside click, and provide keyboard focus, shortcuts, tooltips and accessible names.

## Data compatibility

This update changes timeline navigation, search scope and generated text exports. It does not migrate, duplicate or move existing captures, tasks, comments, reminders or archive folders.

## Verification status

The exact optimized source passed all **30 registered Release suites with 2,704 checks**. Fresh native rendering produced **42 release interface views** and **62 broader views**, including light/dark Weekly popovers, scoped results and the narrow board. The ARM64 build and update package passed clean-copy signature, extraction, fresh-install, replacement, backup and checksum verification. Public GitHub asset verification and the live in-app update remain pending.
