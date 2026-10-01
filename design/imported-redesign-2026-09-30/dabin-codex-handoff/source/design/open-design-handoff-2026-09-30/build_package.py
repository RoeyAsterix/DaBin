#!/usr/bin/env python3
"""Build a local, deterministic-content Open Design reference package."""
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BASE = "b3f8507a77107474f923d9e4af5fc8ad4efe4a00"
NAME = "DaBin-Open-Design-Handoff-0.4.2-build53"

# ID | area | feature | current entry | behavior to retain | owning source basename
ROWS = """
C01|Capture|Robot direct drag and drop|Corner/island robot|Supported native transfers including promised files; stable hover target; save before success|RobotView.swift;InputService.swift
C02|Capture|Explicit robot paste|Hover/focus robot|Control-V and Command-V; no clipboard read merely on hover|RobotView.swift
C03|Capture|Board intake|Inbox and Daily board|Drop/paste while retaining ordinary text-field editing behavior|DailyCaptureView.swift;InboxScreen.swift
C04|Capture|Add menu|Header Add|Paste clipboard; New note; Import files; New task; importing disabled state|BoardView.swift
C05|Capture|Inline quick capture|Inbox composer|Multiline note/task creation; visible destination; save/error/recovery|InboxScreen.swift;DraftArchive.swift
C06|Capture|Supported data and file batches|Input and grouped cards|Text/link/image/PDF/video/doc/generic file; managed copies; multi-file grouping and member access|InputService.swift;GroupedCaptureCard.swift
C07|Inbox|Keep and organize|Inbox card actions|Keep in Workspace without deletion; project filing; convert task; plan Today|InboxScreen.swift
V01|Cards|Fitted previews and fallbacks|Cards and Detail|Image/PDF/video/link/generic states; loading/error/unavailable; no stretching|CapturePreviews.swift;FittedPDFPreview.swift
V02|Cards|Receipt and provenance|Cards and Detail|Immutable date/time; type; best-effort app icon/path; actual saved destination; truthful missing-source fallback|CaptureSourceView.swift;Domain.swift
V03|Cards|Copy individual or grouped content|Upper-right card action and detail|Native clipboard data from saved originals; complete success or failure; no partial group clipboard replacement|CaptureCopyButton.swift;CaptureClipboard.swift
V04|Cards|Comment editing|Card action and Detail|Existing content retained; explicit save; draft recovery and errors|DetailScreen.swift;DraftArchive.swift
V05|Cards|Reminder editing|Card action and Detail|Optional reminder on any capture; accessible clock; visible scheduled/error state|DetailScreen.swift;ReminderClockEditor.swift
V06|Cards|Minimize and expand|Card contextual actions|Persist compact preference; full content remains in details/search|CaptureCards.swift;CapturePresentation.swift
V07|Cards|Link and local file actions|Detail and Workspace context menu|Open original URL/saved file; reveal saved file/folder; copy saved path; missing file feedback|WorkspaceItemCard.swift;AppState.swift
V08|Cards|Pin and project association|Detail and Workspace cards|Persist association/pin; optional project; unfiled remains valid|DetailScreen.swift;WorkspaceItemCard.swift
T01|Tasks|Capture conversion|Card/detail Turn into task|Same record/content/source/receipt; content filter plus Tasks; reveal work plan|DetailScreen.swift;CaptureStore.swift
T02|Tasks|Task status|Task card and detail|Complete/reopen; text/icon as well as color; reminders reflect completion; happy feedback only on success|CaptureCards.swift;CaptureStore.swift
T03|Tasks|Today planning scopes|Today|Today/Upcoming/Completed; project scope; unplanned tasks; unfinished/overdue and due reminders|TodayPlanningScreen.swift
T04|Tasks|Planned day and reschedule|Today and Work plan|Today/Tomorrow/Inbox/custom workday; original receipt and deadline unchanged|TaskPlanningEditor.swift;TaskPlanning.swift
T05|Tasks|Priority effort and ordering|Today and Work plan|None/Low/Medium/High; optional minutes and total effort; reorder; validation|TodayPlanningScreen.swift;TaskPlanningEditor.swift
T06|Tasks|Separate deadline|Work plan Details|Finish-by date/time independent from workday and notification reminder|TaskPlanningEditor.swift
T07|Tasks|Recurrence|Work plan Repeat|None/Daily/Weekdays/Weekly/Monthly; one linked next occurrence; original attachments remain accessible|TaskPlanning.swift;DetailScreen.swift
T08|Tasks|Checklists|Work plan Details|Add/edit/remove/complete; count; 100 steps max and 1-500 characters; helpful validation|TaskPlanningEditor.swift
T09|Tasks|New attachments|Task attachment section|Drop/paste/import more text/files into task; count and previews; no content loss|TaskAttachmentsView.swift;DailyCaptureView.swift
T10|Tasks|Existing attachments and navigation|Workspace and task detail|Attach saved non-task capture; attachment detail; return to parent; no ordinary unlink command in current app|WorkspaceItemCard.swift;TaskAttachmentsView.swift;DetailScreen.swift
T11|Tasks|New task composer|Add and Inbox|Save/cancel/recovery; destination; optional reminder/planning; Command-Return|TaskEditorScreen.swift
R01|Reminders|Date/time and countdown|Reminder clock|Hours 0-99 minutes 0-59; nonzero; begins when saved; reopen never resets|ReminderClockEditor.swift;ReminderSchedule.swift
R02|Reminders|Notification delivery state|Detail/Today/Settings|Permission on first reminder; denied/error/retry/system settings; completion cancellation|ReminderService.swift;SettingsScreen.swift
R03|Reminders|Non-task follow-up actions|Today reminders|Done and Tomorrow; separate from task completion semantics|TodayPlanningScreen.swift
H01|Activity|Daily calendar history|Inbox Activity / More|Calendar selection; previous/next; today; newest first; original receipt date|DailyScreen.swift;BoardView.swift
H02|Activity|Weekly history|Timeline Week|Seven dates ending on chosen date; active days only; whole-week empty; day columns open Daily|WeeklyScreen.swift;AppState.swift
H03|Activity|Task carryover|Daily/Weekly|Unfinished placement; creation-date badge/frame; reminder-day top placement; no duplicate receipt storage|CapturePresentation.swift;AppState.swift
H04|Activity|Content type filters|Timeline and Workspace|All/Text/Links/Files/Media/Tasks; text before Links; task plus original content type|CaptureFilterStrip.swift;Domain.swift
H05|Activity|Automatic hourly summaries|Daily/Weekly feed|Fourth successful auto action groups fixed local hour; exact counts; task separation; expand/collapse in place|HourlyCaptureFeed.swift;HourlyCaptureCard.swift
H06|Activity|Batch actions|Grouped capture card|Expand/minimize; members; group/member copy; grouped removal semantics|GroupedCaptureCard.swift;CaptureCardGroup.swift
S01|Search|Global archive search|Header / Command-K / global shortcut|Immediate focus; saved content/tasks/links/snippets/OCR/scratchpads; grouped dates and previews|SearchScreen.swift;AppState.swift
S02|Search|Day week and all scopes|Weekly Search|Clear scope/date; keyboard access; anchored dismissal; correct selected weekly day|WeeklyScopeActions.swift;AppState.swift
S03|Search|Refinements and context|Search and Workspace filters|Search type/project/app and All/Day/Week; Workspace date/app/origin; Return preserves; nearby context distinguished|SearchScreen.swift;WorkspaceQuery.swift
S04|Search|Empty recovery and Back|Search|Clear refinements or widen dates while retaining query; restore prior selection/route/filter/project|SearchScreen.swift;AppState.swift
S05|Search|Local OCR and text indexing|Details/Search/Settings|Local Vision/PDFKit/text; progress/empty/failure/retry; searchable excerpt/copy; rebuild; bounded work|ContentIndexService.swift;DetailScreen.swift
W01|Workspace|Project spaces|Workspace project control|Create/select/associate optional project; All projects; shared context; selection restoration|LibraryScreen.swift;WorkspaceStore.swift
W02|Workspace|Four connected modes|Workspace|Library/Clipboard/Shelf/Notes; filters and project survive mode changes|LibraryScreen.swift;WorkspaceStore.swift
W03|Workspace|Library browsing|Library|Recognizable cards; responsive columns; pin-only; project/date/app/origin/type filters; item count|LibraryScreen.swift;WorkspaceItemCard.swift
W04|Clipboard|Recent copied material|Clipboard Recent|Automatic copies plus supported manual text/links; new arrivals do not disturb selection; recent not buried by pins|WorkspaceQuery.swift;LibraryScreen.swift
W05|Clipboard|Named reusable snippets|Clipboard Snippets / item menu|Save/rename/remove alias without changing content; alias search; pin access|WorkspaceItemCard.swift;WorkspaceStore.swift
W06|Clipboard|Copy as plain text|Workspace item menu|Text-only clipboard action; no external typing or added Accessibility permission|WorkspaceClipboard.swift
W07|Shelf|Persistent collection|Shelf|Add existing and import/paste/drop; membership survives restart; optional project; remove membership keeps capture|ShelfCaptureController.swift;WorkspaceStore.swift;LibraryScreen.swift
W08|Shelf|Project shelf ZIP|Shelf Export ZIP|Entire project shelf ignores type filter; verified managed files; text/link UTF-8; unique names; no silent overwrite|ShelfExport.swift
W09|Notes|Project and unfiled scratchpads|Workspace Notes|Autosave; saved/not-saved/retry; survives project switch/restart; search only All/Text without app filter; scoped by updated date; no invented source|ScratchpadView.swift;WorkspaceStore.swift
W10|Notes|Convert scratchpad|Notes Save note / Make task|New saved record with original text; scratchpad retained; project destination preserved|ScratchpadView.swift
E01|Export|Copy and text export day|More Export|Complete chosen receipt day; ignores filters; chronological; timestamp/type/source/text/OCR/placeholder; excludes future today|DayExport.swift;BoardView.swift
E02|Export|Copy and text export week|More Export|Complete seven-day receipt range; exact same copy/file text; no carried task duplicates|DayExport.swift;BoardView.swift
E03|Export|Export feedback and dialogs|Export actions|Empty disabled; UTF-8 named file; success/checkmark; cancellation neutral; actionable errors|DayExportUI.swift
A01|Automatic capture|Independent opt-in sources|Header setup and Settings|Clipboard and Screenshots off initially; privacy explanation; channels independent|AutoCaptureSettings.swift;AutoCaptureService.swift
A02|Automatic capture|Pause resume and status|Header/footer/menu bar/Settings|Off/on/paused/excluded/permission/error distinct; immediate stop; existing captures retained|AutoCaptureService.swift;BoardView.swift;StatusBarController.swift
A03|Automatic capture|Screenshot folder authorization|Settings Screenshots|Choose/change/re-authorize folder; security-scoped bookmark; monitor only authorized folder; clipboard independent|ScreenshotFolderMonitor.swift;SettingsScreen.swift
A04|Automatic capture|Fresh baselines and deduplication|Capture service|No old clipboard/files on enable/resume/start; cross-channel duplicate suppression; timestamps/action identity|AutoCaptureService.swift;AutoCaptureFingerprint.swift
A05|Automatic capture|Excluded apps|Settings Excluded applications|Add/remove/restore defaults; DaBin cannot be removed; password defaults; best-effort origin explained|AutoCaptureSettings.swift;SettingsScreen.swift
B01|Buddy|Home and reveal|Robot home and native controller|Corners/compatible island; hidden rest; hover/drag; no flicker; fallback top-right; interacted display|RobotPlacementSettings.swift;CornerController.swift
B02|Buddy|Eating reactions|Successful automatic capture|Ten shuffled reactions; no recent-three repeat; generic token; exact burst count; one bounded popup; failures separate|AutoCaptureRobotCelebration.swift;AutoCaptureRobotPresenter.swift
B03|Buddy|Open close transformation|Robot double-click/Return and board X|Continuous body surface; reserved head/hands/feet; priority/cancellation safe; open current view; responsive close|RobotLifecycle.swift;RobotAppFrameView.swift;CornerController.swift
B04|Buddy|Expressions and accessibility|Robot and empty state|Clamped eased gaze; blink/bored/happy; Reduce Motion static/fade; Quiet; no hidden rendering loop or sound|RobotCharacterView.swift;BoredRobotView.swift;QuickAccess.swift
B05|Window|Move resize expand restore|Frame/drag handle/header|Drag position; edge/corner resize; safe-area expand; compact restored; route/project/draft preserved|CornerController.swift;BoardResizeGeometry.swift
B06|Window|Screens Spaces and focus|Native panels|Display changes recover; no unwanted Space switch/focus theft; decorative hit-test exclusion; screenshot sharing exclusion retained|CornerController.swift;AutoCaptureRobotPresenter.swift
B07|Window|Filter resize behavior|Activity filter change|Top stays anchored; bottom eases; screen clamp/scroll; Reduce Motion immediate|CornerController.swift
P01|Preferences|Theme and appearance|Settings|Dark/light; Purple/Blue/Teal/Green/Rose/Amber; custom/reset; readable resolved accent|ThemeSettings.swift;SettingsScreen.swift
P02|Preferences|Transparency and tooltip control|Settings|35-100 percent opacity in 5 percent steps; solid reset; OS contrast/transparency override; tooltips off keeps accessible labels|ThemeSettings.swift;SettingsScreen.swift
P03|Preferences|Global shortcut choices|Settings Quick access|Enable/disable; two modifier sets; registration errors; quiet mode; no general typing monitoring|QuickAccess.swift;SettingsScreen.swift
P04|Preferences|Manual link preview consent|Settings|Off default; disclosure; earlier/new eligible manual links; turning off stops requests; automatic links never fetched|PreviewService.swift;SettingsScreen.swift
P05|Preferences|Retention and clear history|Settings Clipboard history|Never/7/30/90; protected work; exact confirmation; recoverable removal; progress/results/errors|ClipboardRetentionService.swift;ClipboardRetentionSettings.swift
P06|Preferences|Local archive privacy support|Settings|Open archive; offline policy/data controls; configured support/policy links; rebuild search progress|PrivacyInformation.swift;SettingsScreen.swift
P07|Preferences|Updates and visible version|Settings first section|Direct Get updates/check/install/release link; truthful installed status; Store-managed alternative; no silent checks|SoftwareUpdateService.swift;SettingsScreen.swift
P08|Preferences|Complete Quit|Settings and menu bar|Terminate process; preserve drafts; ask only if unsaved data cannot persist; hide X is different|SettingsScreen.swift;ApplicationCoordinator.swift
D01|Recovery|Recently Deleted and Undo|More / removal banner|Confirmation; undo latest; restore; task families/reminders; no external original deletion|CaptureRemoval.swift;TrashScreen.swift
D02|Recovery|Permanent deletion|Recently Deleted|Separate confirmation; journaled cleanup; error handling; never confused with collapse or shelf membership removal|TrashScreen.swift;CaptureStore.swift
D03|Recovery|Verified archive backup restore|More|Captures/originals/projects/shelf/snippets/notes/trash; checksums; additive no overwrite; conflicts/busy/draft handling|ArchiveBackup.swift;AppState.swift
D04|Recovery|Local dated archive|Storage and Finder reveal|Year/named numbered month/day folders; unique capture folder; authoritative DB; source originals kept; failed work recoverable|DailyArchive.swift;CaptureRepository.swift
D05|Recovery|Draft and navigation recovery|Composer/detail/Back/restart|Unfinished edits separate from saved captures; visible destination; route/project/selection retained; failed save reported|DraftArchive.swift;AppState.swift
K01|Access|Native menus and keyboard|Application/menu bar/controls|Status item Open/state/Pause/Settings/Quit; app menu About/updates/Open/focus/Search/Settings/Edit/Hide/Quit; shortcuts; accessible focus|ApplicationMenu.swift;StatusBarController.swift
K02|Access|First launch and resume|Application coordinator|First launch shows Inbox; later launch quiet; same-session reopen resumes route; global capture selects Daily|ApplicationCoordinator.swift;CornerController.swift
""".strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    fields = ["id", "area", "feature", "current_entry", "behavior_to_preserve", "source_files", "proposed_location", "prototype_or_spec_evidence", "verification_status"]
    rows = []
    for line in ROWS.splitlines():
        ident, area, feature, entry, behavior, sources = line.split("|")
        paths = ["native/Sources/DaBin/" + name for name in sources.split(";")]
        for path in paths:
            if not (ROOT / path).is_file():
                raise RuntimeError("Missing source: " + path)
        rows.append([ident, area, feature, entry, behavior, ";".join(paths), "TO COMPLETE BY OPEN DESIGN", "TO COMPLETE BY OPEN DESIGN", "PENDING REDESIGN"])
    if len({row[0] for row in rows}) != len(rows):
        raise RuntimeError("Duplicate feature ID")
    with (HERE / "FEATURES.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(fields)
        writer.writerows(rows)

    assets = HERE / "assets"
    assets.mkdir(exist_ok=True)
    for source, target in [
        (ROOT / "native/Resources/robot.svg", "original-robot.svg"),
        (ROOT / "design/onepager/assets/DaBin-logo.png", "logo-reference.png"),
    ]:
        shutil.copyfile(source, assets / target)

    refs = HERE / "reference-screens"
    current = refs / "current-build53"
    history = refs / "historical-build50"
    current.mkdir(parents=True, exist_ok=True)
    history.mkdir(parents=True, exist_ok=True)
    render_root = Path("/private/tmp/DaBin-Review-Readability-Final-20260930/renders")
    screen_records = []
    for view in ["inbox", "today-long", "library", "clipboard", "shelf", "scratchpad", "new-note", "task-detail", "scoped-search", "settings"]:
        for variant in ["light-380-minimum", "dark-760"]:
            filename = "native-" + view + "-" + variant + ".png"
            dest = current / filename
            source = render_root / filename
            if source.exists():
                shutil.copyfile(source, dest)
            elif not dest.exists():
                raise RuntimeError("Missing current fixture screenshot: " + filename)
            screen_records.append({"file": str(dest.relative_to(HERE)), "version": "0.4.2 (53)", "kind": "synthetic native view QA render", "sha256": sha(dest)})
    baseline_root = ROOT / "docs/review-2026-09-30/baseline"
    for filename in ["native-view-buddy-daily-dark-380x680.png", "native-view-buddy-task-countdown-dark-380x680.png", "native-view-buddy-task-attachments-light-720x740.png", "native-view-buddy-image-detail-light-380x740.png", "native-view-buddy-robot-frame-dark-400x670.png"]:
        dest = history / filename
        shutil.copyfile(baseline_root / filename, dest)
        screen_records.append({"file": str(dest.relative_to(HERE)), "version": "historical build 50", "kind": "synthetic native view QA render; superseded header/navigation", "sha256": sha(dest)})
    (HERE / "SCREEN_PROVENANCE.json").write_text(json.dumps(screen_records, indent=2) + "\n", encoding="utf-8")

    staging = Path(tempfile.mkdtemp(prefix="dabin-opendesign-")) / NAME
    staging.mkdir()
    handoff_relative = HERE.relative_to(ROOT)
    shutil.copytree(HERE, staging / handoff_relative, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copyfile(ROOT / "OPEN_DESIGN_HANDOFF.md", staging / "OPEN_DESIGN_HANDOFF.md")
    shutil.copyfile(HERE / "OPEN_DESIGN_PROMPT.txt", staging / "START_HERE.txt")
    native_files = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASE, "native"], cwd=ROOT, text=True).splitlines()
    source_count = 0
    for name in native_files:
        if not name.startswith(("native/Sources/", "native/Tests/", "native/Resources/", "native/scripts/", "native/Config/", "native/DaBin.xcodeproj/", "native/UpdateTools/")) and name not in ("native/ARCHITECTURE.md", "native/README.md", "native/.gitignore"):
            continue
        data = subprocess.check_output(["git", "show", BASE + ":" + name], cwd=ROOT)
        target = staging / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        if (ROOT / name).stat().st_mode & 0o111:
            target.chmod(0o755)
        source_count += 1

    (staging / "README.txt").write_text(
        "DaBin Open Design redesign handoff\n\n"
        "Start with START_HERE.txt, then OPEN_DESIGN_HANDOFF.md.\n"
        "Baseline: DaBin 0.4.2 (53), commit " + BASE + ".\n"
        + str(len(rows)) + " feature-preservation rows; 25 labeled synthetic reference images.\n\n"
        "The design brief and source map are under design/open-design-handoff-2026-09-30/.\n"
        "FEATURES.csv is the editable checklist Open Design must complete.\n"
        "native/ contains a frozen source/test/resource/build reference snapshot.\n"
        "This is a handoff, not an application installer or a new redesign.\n"
        "Historical build-50 images are labeled and must not override current source.\n"
        "No live capture archive, clipboard data, credentials or binaries are included.\n"
        "The original obsolete handoff is intentionally excluded.\n",
        encoding="utf-8")
    entries = [{"path": str(p.relative_to(staging)), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(staging.rglob("*")) if p.is_file()]
    manifest = {"product": "DaBin", "version": "0.4.2", "build": 53, "source_commit": BASE, "created_date": "2026-09-30", "purpose": "Open Design redesign with complete feature preservation", "feature_count": len(rows), "reference_image_count": len(screen_records), "source_file_count": source_count, "files": entries}
    (staging / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    output = ROOT / "output/handoffs"
    output.mkdir(parents=True, exist_ok=True)
    zipped = output / (NAME + ".zip")
    with zipfile.ZipFile(zipped, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(staging.rglob("*")):
            if path.is_file():
                archive.write(path, str(path.relative_to(staging.parent)))
    with zipfile.ZipFile(zipped) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC check failed")
        for entry in entries:
            payload = archive.read(NAME + "/" + entry["path"])
            if hashlib.sha256(payload).hexdigest() != entry["sha256"]:
                raise RuntimeError("ZIP hash mismatch: " + entry["path"])
        forbidden = [name for name in archive.namelist() if "/.git/" in name or name.endswith((".p12", ".key", ".sqlite", ".db", ".app", ".dabinbackup")) or "/build/" in name]
        if forbidden:
            raise RuntimeError("Unexpected package contents: " + str(forbidden))
    receipt = {"zip": zipped.name, "bytes": zipped.stat().st_size, "sha256": sha(zipped), "features": len(rows), "images": len(screen_records), "source_files": source_count, "total_files": len(entries) + 1, "zip_crc": "PASS", "all_file_hashes": "PASS", "scope_check": "PASS"}
    (output / (NAME + "-verification.json")).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))

if __name__ == "__main__":
    main()
