from pathlib import Path
import csv,json,shutil
R=Path(__file__).resolve().parent; root=R.parent
rows=list(csv.DictReader(open(root/'source/design/open-design-handoff-2026-09-30/FEATURES.csv')))
routes={
'C':'inbox.html','V':'capture-detail.html','T':'task-detail.html','R':'reminder.html','H':'activity.html','S':'search.html','W':'workspace.html','E':'export.html','A':'settings.html','B':'robot.html','P':'settings.html','D':'recently-deleted.html','K':'robot.html'}
override={'C01':'robot.html','C02':'robot.html','C04':'inbox.html','T03':'today.html','T04':'today.html','T05':'today.html','T11':'new-task.html','R03':'today.html','H02':'weekly.html','S05':'capture-detail.html','W04':'clipboard.html','W05':'clipboard.html','W06':'clipboard.html','W07':'shelf.html','W08':'shelf.html','W09':'notes.html','W10':'notes.html','E02':'export.html?scope=Week','D03':'backup.html','D04':'settings.html','D05':'new-note.html','K02':'inbox.html'}
locations={
'C01':'Robot direct drop; Inbox and task attachment drop targets','C02':'Robot Paste; active panel paste excluding editable fields','C03':'Inbox composer and board paste/drop','C04':'Header + menu: Paste, New note, Import files, New task','C05':'Inbox quick composer; explicit destination and restored draft','C06':'Grouped file card with clickable members; native payload contract',
'C07':'Capture actions: Keep, File to project, Turn into task, Plan for Today',
'V01':'Preview-led card and capture detail original content pane','V02':'Card receipt/source; Detail provenance block','V03':'Upper-right Copy; grouped native clipboard state dialog','V04':'Detail Comment; Save changes; recovered edit banner','V05':'Detail Reminder link; separate reminder screen','V06':'Capture Actions → Minimize / Expand preview','V07':'Detail Open original; File location native state dialog','V08':'Detail project + pin; card action equivalents',
'T01':'Turn into task → same record in Task Detail','T02':'Today checkbox; task detail Complete/Reopen','T03':'Today / Upcoming / Completed; unplanned, unfinished and reminders sections','T04':'Task menu Today/Tomorrow/clear; Work plan custom date','T05':'Work plan Priority/Effort; Today Move earlier/later','T06':'Work plan Deadline, separate from planned date and reminder','T07':'Work plan Repeat; Previous and Next occurrence links','T08':'Checklist rows; add/remove/edit/check; explicit save','T09':'Task Attachments → Import / Paste; task panel drop','T10':'Task Attachments → Saved item; child detail → Parent','T11':'Add → New task; destination label; recovered draft',
'R01':'Reminder Date & time / Countdown; persisted target time','R02':'Reminder and Settings → Notification status native dialog','R03':'Today non-task reminder row → Done / Tomorrow',
'H01':'Activity Day date group; previous/next/calendar/Today','H02':'Activity Week, seven days ending on selected date','H03':'Activity Still open section; original receipt label','H04':'Context type strip: All, Text, Links, Files, Media, Tasks','H05':'Activity hourly summary; disclosure and named collapse action','H06':'Grouped file card → member detail; Actions minimize; native atomic copy contract',
'S01':'Header Search / ⌘K; results across text, OCR, filenames, snippets and notes','S02':'Search All/Day/Week; Activity scoped search buttons','S03':'Search type/project/app; nearby context; Workspace refinements','S04':'Empty Search → Clear refinements / Search all dates; Back','S05':'Detail recognized text/status; Settings rebuild index',
'W01':'Shared project selector; Create project; detail association','W02':'Workspace Library / Clipboard / Shelf / Notes','W03':'Library preview grid/list; type strip and refinement dialog','W04':'Clipboard Recent, separate Pinned and Snippets views','W05':'Capture Actions → Name / Rename / Remove snippet alias','W06':'Capture Actions and Detail → Copy as plain text','W07':'Shelf Add from Library / intake; Remove from shelf; keep capture','W08':'Shelf Export shelf, full selected project collection','W09':'Notes project/unfiled scratchpads; autosave status/retry','W10':'Notes Save as note / Make task; scratchpad retained',
'E01':'Activity Day → Export → Copy / Text file','E02':'Activity Week → Export → Copy / Text file','E03':'Export preview; empty disabled; native save state dialog',
'A01':'Settings Auto capture independent source switches','A02':'Header auto status / Pause / Resume; Settings Source status','A03':'Settings Screenshot folder → Choose folder native contract','A04':'Auto capture native contract; fresh-baseline status copy','A05':'Settings Excluded apps; DaBin immutable; restore defaults',
'B01':'Settings Robot home; Robot entry study; native safe-area contract','B02':'Robot reaction study with ten choices, shuffle and burst count','B03':'Thin app frame; hide/restore; native transition storyboard','B04':'Robot study plus Settings Quiet / Reduce Motion','B05':'Header drag region; outer resize handle; expand/restore','B06':'Native placement states; focus, Spaces and display contract','B07':'Bounded header and content scroll; native bottom resize contract',
'P01':'Settings Appearance preset/custom/reset; light/dark','P02':'Settings opacity / solid reset / hover help / accessibility','P03':'Settings Robot & access predefined shortcuts/status','P04':'Settings Privacy manual link preview opt-in','P05':'Settings retention / clear eligible copies; exact count confirmation','P06':'Settings archive / privacy / support / rebuild index','P07':'Settings installed version / Get updates / Store-build behavior','P08':'Settings Quit; neutral header X hides only',
'D01':'Capture removal confirmation; toast Undo; Recently Deleted Restore','D02':'Recently Deleted Delete permanently separate confirmation','D03':'Backup & restore; fixture import/export and native conflict states','D04':'Settings Open local archive native contract','D05':'Inbox/New note/New task and Detail recoverable drafts; restored route context','K01':'Robot study status/application menus; in-document keyboard shortcuts','K02':'Inbox first-run layout; same-session hide/reopen; native quiet launch contract'}
# A feature may have implemented browser behavior and still require native verification.
native_only={'C01','C02','V03','V07','R02','S05','A03','A04','B01','B03','B06','B07','P03','P04','P06','P07','P08','D04','K01','K02'}
partial={'C06','V01','V02','H03','H06','A01','A02','B02','B04','B05','P05','D03','D05'}
contracts={
'Capture':('Input → validation → saving → committed or recoverable failure. No success animation before persistence.','Preserve native NSItemProvider promised-file loading, supported transfers and file security scope. Reject unsupported folder/alias/symlink intake without claiming successful capture. Retain destination on interrupted saves. Browser imports keep data URLs only in isolated storage, have an explicit 8 MB per-file fixture bound and never claim native parity.'),
'Inbox':('Untriaged → optional project/task/workday → kept in Workspace. No record replacement.','Keep sets protection against cleanup. A project association is optional. The original receipt, content and type remain immutable. Empty destination shows capture guidance; recovered draft discloses Inbox/project. A storage failure retains the draft and reports failure.'),
'Cards':('Available → preview loading → ready, unavailable, unsupported or failed. Actions stay discoverable.','Preview fitting uses contain, not cropping. Source metadata is best effort; absent source path says not supplied. Native copy validates every grouped payload before replacing clipboard. Comment edits remain a draft until Save changes. Minimize never hides content from search or Detail. Deletion and collapse are separate named actions.'),
'Tasks':('Capture → task on the same ID → planned → completed/reopened.','Plan date, deadline, reminder and receipt are independent. Priority None/Low/Medium/High; optional effort 1–10080 minutes; checklist max 100 rows of 1–500 characters. Recurrence creates one linked next occurrence using original cadence; attachments remain on the completed occurrence. Reopening cannot spawn an additional next occurrence. Attachment navigation retains the parent; ordinary unlinking is not offered.'),
'Reminders':('None → date/time or countdown draft → saved target → due / canceled / delivery error.','Countdown permits 0–99 hours and 0–59 minutes, nonzero total. Its target is calculated at save, stored absolutely and never reset by opening or comment editing. First native scheduling requests notification permission. Denial exposes System Settings and retry; task completion cancels delivery. Non-task Done removes the reminder, Tomorrow reschedules without task conversion.'),
'Activity':('Selected receipt day ↔ seven-date range ending on selected day → scoped search/export.','Newest receipts first. Weekly hides truly empty columns but labels the full range; whole-week empty state remains usable. Task carryover is computed presentation, never duplicated receipt storage; reminded carried tasks appear on their reminder day. Fourth successful automatic action within the same local clock hour forms a summary, 1–3 remain individual. Tasks are separated. Collapse actions retains scroll and cannot delete.'),
'Search':('Focused query → scoped/refined matches → detail → Back to prior query, refinements and scroll.','All/Day/Week uses receipt dates for captures and updated dates for scratchpads. Scratchpads require All/Text and no app filter; do not invent app provenance. Nearby context is labeled separately from actual matches. Empty results can clear refinements or broaden dates without clearing text. OCR/PDF/doc indexing is local, bounded, and exposes progress/no-text/error/retry; native implementation retains source limits.'),
'Workspace':('Shared optional project → Library/Clipboard/Shelf/Notes → selected resource → return.','Recent is chronological and separate from Pinned so many pins cannot bury new copies. A snippet is an alias, never replacement content. New arrivals do not reset the browsing position. Shelf membership and removal are separate from saved-record deletion; its ZIP ignores current type/app/date filters and includes the full selected project shelf with collision-safe names. Notes autosave by project/unfiled and remain after conversion; failures retain edits and expose retry.'),
'Export':('Selected day/week → complete receipt payload → copy/save picker → success, neutral cancel or actionable failure.','Copy and file output use the same UTF-8 bytes, chronological original receipt order, type/time/source if known, text/OCR or an honest no-preview marker. Ignore active content filters and project refinements for a complete Activity export. Avoid carried-task duplicates and future receipts for today. Empty scope disables actions. Day name DaBin-YYYY-MM-DD.txt; week names identify both boundaries.'),
'Auto Capture':('Independent off sources → explicit consent → fresh baseline → active / shared paused / excluded / permission error / failed.','Clipboard and screenshot channels remain independent. Screenshot folder selection stores a security-scoped authorization; revoked access cannot disable clipboard. DaBin is permanently excluded. Password-source exclusions are best effort, not perfect sensitive-data detection. Enable/resume never replays existing clipboard/folder content. Dedup images across channels before persistence/counting. Generic robot tokens only after successful save; no automatic website preview requests.'),
'Robot':('Hidden → reveal → ready → saving → saved reaction → retreat; opening supersedes presentation.','See ROBOT_MOTION.md for all ten reactions, previous-three exclusion, exact burst counts, one bounded presenter, cancellation endpoints and reserved geometry. Native AppKit handles display safe areas, Spaces and sharing exclusion. Browser animation controls explicitly identify the simulation and cannot prove OS behavior.'),
'Preferences':('Persisted preference → user change → apply/registration → effective state or recoverable error.','Source presets and custom sRGB accents resolve for contrast. Opacity 35–100% in 5% increments; system Reduce Transparency forces effective opacity 100 without erasing the preference. Navigation/cards remain opaque. Tooltips off keeps accessibility labels. Link previews are off initially and only eligible manual links may request networking. Direct updates are user initiated with verify/backup/install gates; Store build excludes the direct helper.'),
'Data':('Saved → recoverable trash → restore or separately confirmed permanent deletion.','Operate on capture/task family; imported external originals are never deleted. Native journaled cleanup reports partial I/O failure without losing recovery metadata. Restore retains original content/date/project; past reminder handling is explicit. Backups include metadata, originals, projects, memberships, snippets, notes and trash, verify checksums and restore additively. Conflicts block overwrite. Corrupt packages and pending drafts block application.'),
'Keyboard':('Entry shortcut/menu → focused route → innermost popover → return focus or hide.','Preserve native responder-chain cut/copy/paste/select-all/undo/redo and composition. Do not intercept paste in text editors. First launch opens Inbox; later launch is quiet; same-session reopen resumes route. Global clipboard-save explicitly selects Daily before intake. Global registration has two predefined choices and disabled/conflict states. Browser keyboard testing does not prove native menu/global registration.'),
}
# Resolve native matrix area spellings through feature ID rather than assuming spreadsheet labels.
group_for={'C':'Capture','V':'Cards','T':'Tasks','R':'Reminders','H':'Activity','S':'Search','W':'Workspace','E':'Export','A':'Auto Capture','B':'Robot','P':'Preferences','D':'Data','K':'Keyboard'}
spec=['# Feature preservation and native implementation contracts\n','Baseline: DaBin 0.4.2 (53), frozen source snapshot supplied by the user. This is an editable design specification, not a native release or a claim of OS parity.\n','Every matrix row has a destination below. Browser coverage status describes evidence availability, not a claim that every scenario passed. See QA_REPORT.md for executed checks and unverified native work.\n']
for g,(flow,contract) in contracts.items():spec+=['## '+g+' contract\n',flow+'\n',contract+'\n']
for r in rows:
 i=r['id'];route=override.get(i,routes[i[0]]);r['proposed_location']=locations[i]
 status='NATIVE SPECIFICATION; native verification pending' if i in native_only else 'PARTIAL BROWSER + NATIVE SPEC; native verification pending' if i in partial else 'BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending'
 r['prototype_or_spec_evidence']=route+'; open-design-v3/specs/FEATURE_CONTRACTS.md#'+i.lower()+'; open-design-v3/qa-results.json'
 r['verification_status']=status
 spec+=['## '+i+'\n','**'+r['feature']+'**\n','- Proposed location: '+locations[i]+'.\n','- Browser route: ['+route+'](../../'+route+').\n','- Preserve: '+r['behavior_to_preserve']+'.\n','- State behavior: apply the '+group_for[i[0]]+' contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.\n','- Native ownership: '+r['source_files']+'.\n','- Evidence status: '+status+'.\n']
(R/'specs/FEATURE_CONTRACTS.md').write_text('\n'.join(spec))
with open(R/'FEATURES.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
(R/'NAVIGATION_MAP.md').write_text('''# Old → new navigation and interaction review

The chosen system keeps existing labels and adds Activity as a peer destination. No permanent sidebar. All screens retain the source robot identity and native geometry contract.

| Build 53 entry | Redesigned entry | Change |
|---|---|---|
| Inbox primary tab | Inbox primary tab | Preview-led cards, one composer, progressive card actions |
| Today primary tab | Today primary tab | Workday first; separate Upcoming and Completed |
| Workspace primary tab | Workspace primary tab | Shared project selector and four named collections |
| Inbox Activity / More | Activity primary tab | One click from any main destination |
| Daily / Weekly | Activity Day / Week | Stable centered date group and scope-specific search/export |
| Add icon | Header + menu | Four named actions retained |
| Auto icon and footer setup | Status next to logo + Settings | Explicit off/on/paused/error vocabulary |
| Detail work-plan accordion | Task detail two-pane expanded / stacked compact | Original capture stays alongside plan |
| Settings gear | Settings gear | Direct access preserved; no intermediate menu |
| More → Trash | Settings → Recently Deleted | Removal toast provides immediate Undo |

## Alternatives considered at actual CSS size

1. **Labeled top navigation — selected.** One click between the four primary places. Predictable position in compact and expanded views. Two bounded chrome rows preserve discoverability without a sidebar.
2. **Destination switcher.** Saves a row at minimum height. Switching destinations requires open + choose (two clicks) and hides the product structure. Keep as a future option only if actual user observation warrants it.
3. **Bottom destination dock.** Familiar touch model but farther from desktop capture/search controls and competes with status/footer. Rejected for this macOS-first product.

The design-review page displays the two compact header alternatives at 380 CSS px. This is an expert design comparison, not user research or a timed study.

## Interaction counts — predicted from source/control paths

Text entry, file selection and OS permission actions are reported separately; these are expert path counts, not measured user task times.

| Same task | Build 53 path | New path | New click count |
|---|---|---|---:|
| Quick text capture | Inbox composer → submit | Inbox composer → Capture | 1 after text entry |
| Convert capture to task | Detail/card conversion | Actions → Turn into task | 2 from card |
| Open global search | Header search / ⌘K | Header search / ⌘K | 1 / keyboard |
| Copy a capture | Upper-right copy | Upper-right copy | 1 |
| Switch existing project | Project menu → selection | Project selector → selection | 2 |
| Add reminder from task | Detail → clock → Save | Reminder → choose → Save | 2 plus date entry |
| Export selected day | Day scope menu → export | Export → Export text file | 2 plus native save panel |
| Open Settings | Gear | Gear | 1 |
| Move between core places | Primary tabs or Activity link | Labeled primary tab | 1 |

No empirical before/after performance improvement is claimed. Reassess with the same fixture, window size and input device after native implementation.
''')
(R/'IMPLEMENTATION_MAP.md').write_text('# Native source mapping\n\nDo not copy browser storage into the shipping architecture. Source ownership stays unchanged. HTML/JS are interaction references.\n\n| Feature | Proposed location | Existing source owner |\n|---|---|---|\n'+'\n'.join('| '+r['id']+' '+r['feature']+' | '+r['proposed_location'].replace('|','/')+' | '+r['source_files'].replace('native/Sources/DaBin/','').replace(';','; ')+' |' for r in rows)+'\n\nImplement in the existing SwiftUI/AppKit components; retain versioned Core Data payloads, managed-file storage, state machines and tests. No migration or production installation is part of this handoff.\n')
(R/'DESIGN.md').write_text('''# DaBin v3 design system

The visual identity comes from the supplied build-53 source. Canonical source palette is recorded in ../brand-spec.md. Editable component styles: tokens.css. Editable behavior: model.js, views.js, settings.js, interactions.js, events.js. Rebuild standalone screens with `python3 open-design-v3/build.py`.

## Product posture

A small native companion: capture quickly, optionally connect to a project, act, retrieve. No permanent sidebar, oversized mascot, account flow or invented cloud/AI service. This redesign preserves tasks and grouped files from the latest handoff.

## Tokens

| Role | Light | Dark |
|---|---|---|
| Canvas | #FDFCFE | #1D1C21 |
| Surface | #FFFFFF | #252328 |
| Foreground | #2B2731 | #EBEAED |
| Secondary | #615A69 | #A9A6AE |
| Hairline | #E3E0E6 | #3C3940 |
| Soft selection | #F3F1F5 | #2D2A30 |
| Default readable accent | #6D5387 | #AB92C6 |

Source presets: Purple #6D5387, Blue #386A9A, Teal #287875, Green #47763E, Rose #A34D73, Amber #956515. Custom source colors are mixed toward black/white until readable; never rewrite the chosen preference. Robot shell remains identity-purple. Semantic success, warning and error use labels and shapes as well as color.

Display: SF Pro Rounded / Avenir Next / native fallback. Body: SF Pro Text / Apple system. Numerics and receipt times: SF Mono / system mono. Sizes 11, 12, 14, 15/16, 18, 26/30. Body 1.5–1.65 line height. Compact body is 13–14px, secondary 11–12px. Headings use negative tracking, small labels positive tracking.

Spacing: 4/8/12/16/20/28/32. Cards 12px radius, inputs/buttons 8px, app shell 17px. Hairline card boundaries; shadows only for frame separation/dialogs. Keep visual accent concentrated on selected main navigation and the primary action. Metallic gradients belong only to the robot hardware.

## Component states

- Buttons: default, hover, pressed, focus-visible, disabled; icon-only controls have permanent accessible names and optional hover help. Desktop target 32–34px; coarse-pointer 44px.
- Tabs: selected text/shape and aria-current; repeated project context survives collection changes.
- Capture card: source/receipt, fitted original preview, optional task state, copy, Keep and Actions. Expanded/minimized preserves searchability.
- Task: checkbox with accessible Complete/Reopen name, text status, plan metadata and explicit work-plan editor.
- Grouped files: one container with individual member links; group copy is atomic native behavior.
- Hourly capture group: four or more successful automatic actions per local hour; collapse is distinct from deletion and retains position.
- Dialog: named title, native modal focus containment, Escape, backdrop dismissal and return focus.
- Empty state: specific recovery action; no fabricated content or statistics.
- Error: visible action-specific message, retained draft/record and retry path.

## Resizing contract

Native minimum 380×430 content / 400×480 outer. Frame reserves 10px sides, 32px head and 18px feet. Main chrome remains bounded; only content scrolls. Above 700px container width, preview grids and task details gain two columns. Below that, one readable list and stacked detail panes. At browser widths below 400, this reference gracefully fits the viewport; shipping native minimum remains unchanged. Compact/expanded share state. Browser drag/resize demonstrates the idea but does not prove AppKit geometry.

## Data and state boundaries

Fictional Northstar Studio and Mori fixtures only. Browser localStorage is a review mechanism under a project-specific namespace, not production storage. New files are retained as fixture data URLs with an explicit 8 MB per-file ceiling. Exported JSON is labeled a design fixture; native .dabinbackup has a separate verified contract. Native-only operations open labeled explanations instead of false success messages.

## Screen inventory

See screen-index.json and the root launcher. Every distinct route has its own standalone HTML file. Settings contains real product preferences, not designer viewport/theme controls. Robot motion controls belong to the explicitly labeled interaction study.
''')
(R/'README.md').write_text('''# DaBin Open Design v3

Open ../index.html, then Open DaBin. Product screens are standalone HTML with inline styles/scripts; serve the folder through the project preview for consistent navigation, clipboard permissions and local asset ZIP export.

This is a browser design reference for the native macOS app. No native app was installed, built, published or modified. The supplied frozen source is preserved in ../source/.

- DESIGN.md: tokens, typography, layout and components.
- FEATURES.csv: all 80 preservation rows with locations/evidence/status.
- NAVIGATION_MAP.md: alternatives, old-to-new map and estimated interaction counts.
- IMPLEMENTATION_MAP.md: native owner for every feature.
- specs/FEATURE_CONTRACTS.md: complete feature state contracts.
- specs/ROBOT_MOTION.md: ten reactions, lifecycle, native placement and interruption.
- QA_REPORT.md and qa-results.json: performed checks, limits and remaining native gates.
- ../design-review.html: header comparison, component examples, current source references.

Editable sources: tokens.css, model.js, views.js, settings.js, interactions.js, events.js. Run `python3 open-design-v3/build.py` after edits. Root generated HTML files are delivery outputs. `verify.py` runs syntax, fixture behavior, route and markup checks using local JavaScriptCore; it does not render a browser.

## Local review flows

1. Inbox → capture a note → Actions → project → Turn into task → edit checklist/plan → Save changes.
2. Clipboard → Snippets → name/rename alias → Search → copy plain text.
3. Workspace → Shelf → filter Links → Export shelf; export still includes the full selected project shelf.
4. Notes → switch project → write → Save as note / Make task; scratchpad stays intact.
5. Task → reminder countdown → reopen; stored target time remains unchanged.
6. Capture → Recently Deleted → Undo or Restore; permanent deletion asks separately.

OS file promises, binary pasteboards, system notifications, native folder authorization, window/Spaces behavior, archive integrity and direct/Store updates require native implementation verification. Do not interpret a browser demonstration as completion of those gates.
''')
print('Mapped',len(rows),'features; wrote system, navigation, implementation and native contracts.')
