from pathlib import Path
from shutil import copy2
import json

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/pdf/DaBin-Quick-Guide.pdf"
DOC_COPY = ROOT / "docs/DaBin-Quick-Guide.pdf"
QA_PATH = ROOT / "tmp/pdfs/layout-check.json"
OUT.parent.mkdir(parents=True, exist_ok=True)
QA_PATH.parent.mkdir(parents=True, exist_ok=True)

NORMAL = "Helvetica"
BOLD = "Helvetica-Bold"
W, H = landscape(A4)

INK = colors.HexColor("#30283D")
PURPLE = colors.HexColor("#72508E")
PURPLE_DARK = colors.HexColor("#4A365C")
BODY = colors.HexColor("#625B6A")
MUTED = colors.HexColor("#6D6574")
PALE = colors.HexColor("#F3EDF7")
PALE_2 = colors.HexColor("#F8F5FA")
PAPER = colors.HexColor("#FDFCFD")
LINE = colors.HexColor("#E2D9E8")
MINT = colors.HexColor("#DDF4ED")
MINT_INK = colors.HexColor("#35695C")
WHITE = colors.white

c = canvas.Canvas(str(OUT), pagesize=(W, H), pageCompression=1)
c.setTitle("DaBin | Everything your day leaves behind")
c.setAuthor("DaBin")
c.setSubject("A complete one-page guide to DaBin for macOS")
c.setCreator("DaBin one-page guide")

text_blocks = []
card_checks = []


def rect(x, top, width, height, fill, radius=0, stroke=None, line_width=0.7):
    c.setFillColor(fill)
    c.setStrokeColor(stroke or fill)
    c.setLineWidth(line_width)
    c.roundRect(
        x,
        H - top - height,
        width,
        height,
        radius,
        fill=1,
        stroke=int(stroke is not None),
    )


def rule(x1, y1, x2, y2, color=LINE, width=0.7):
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.line(x1, H - y1, x2, H - y2)


def text(value, x, top, size=10, font=NORMAL, color=INK):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawString(x, H - top - size * 0.82, value)


def right(value, x, top, size=9, font=NORMAL, color=BODY):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawRightString(x, H - top - size * 0.82, value)


def centered(value, x, top, width, size=9, font=NORMAL, color=BODY):
    c.setFont(font, size)
    c.setFillColor(color)
    c.drawCentredString(x + width / 2, H - top - size * 0.82, value)


def paragraph(value, x, top, width, size=9, leading=11, color=BODY, font=NORMAL, max_height=None):
    p = Paragraph(
        value,
        ParagraphStyle(
            "p",
            fontName=font,
            fontSize=size,
            leading=leading,
            textColor=color,
            spaceAfter=0,
            allowWidows=0,
            allowOrphans=0,
        ),
    )
    _, height = p.wrap(width, H)
    if max_height is not None:
        assert height <= max_height, (value, height, max_height)
    p.drawOn(c, x, H - top - height)
    text_blocks.append({"text": value, "x": x, "top": top, "width": width, "height": height})
    return height


def image(path, x, top, width, height):
    c.drawImage(ImageReader(str(path)), x, H - top - height, width=width, height=height, mask="auto")


def icon(kind, x, top, size=18, color=PURPLE):
    """Small line icons drawn as vectors so the guide remains sharp when printed."""
    c.saveState()
    c.translate(x, H - top - size)
    c.scale(size / 24, size / 24)
    c.setStrokeColor(color)
    c.setFillColor(color)
    c.setLineWidth(1.65)
    c.setLineCap(1)
    c.setLineJoin(1)

    if kind == "capture":
        c.roundRect(3, 4, 18, 15, 3, stroke=1, fill=0)
        c.circle(12, 11.5, 4.2, stroke=1, fill=0)
        c.line(7, 19, 9, 22)
        c.line(9, 22, 15, 22)
        c.line(15, 22, 17, 19)
    elif kind == "calendar":
        c.roundRect(3, 3, 18, 17, 3, stroke=1, fill=0)
        c.line(3, 15.5, 21, 15.5)
        c.line(8, 19, 8, 22)
        c.line(16, 19, 16, 22)
        for cx in (7.5, 12, 16.5):
            c.circle(cx, 10.5, 0.75, stroke=0, fill=1)
        c.circle(7.5, 6.8, 0.75, stroke=0, fill=1)
        c.circle(12, 6.8, 0.75, stroke=0, fill=1)
    elif kind == "search":
        c.circle(10, 14, 6.5, stroke=1, fill=0)
        c.line(15, 9, 21, 3)
        c.line(7, 14, 13, 14)
        c.line(7, 11, 11, 11)
    elif kind == "card":
        c.roundRect(3, 4, 18, 16, 3, stroke=1, fill=0)
        c.line(7, 16, 17, 16)
        c.line(7, 12, 14, 12)
        c.line(7, 8, 12, 8)
        c.circle(18.5, 6.5, 3.2, stroke=0, fill=1)
        c.setStrokeColor(WHITE)
        c.setLineWidth(1.4)
        c.line(17, 6.5, 20, 6.5)
    elif kind == "task":
        c.roundRect(3, 3, 18, 18, 5, stroke=1, fill=0)
        p = c.beginPath()
        p.moveTo(7, 12)
        p.lineTo(10.5, 8)
        p.lineTo(17.5, 16)
        c.drawPath(p, stroke=1, fill=0)
    elif kind == "export":
        c.roundRect(4, 3, 16, 12, 2.5, stroke=1, fill=0)
        c.line(12, 8, 12, 22)
        c.line(12, 22, 8, 18)
        c.line(12, 22, 16, 18)
    elif kind == "auto":
        c.circle(12, 12, 9, stroke=1, fill=0)
        c.line(12, 7, 12, 17)
        c.line(7, 12, 17, 12)
        c.circle(12, 12, 2.2, stroke=0, fill=1)
    elif kind == "settings":
        c.circle(12, 12, 4, stroke=1, fill=0)
        for angle in range(0, 360, 45):
            c.saveState()
            c.translate(12, 12)
            c.rotate(angle)
            c.line(0, 6, 0, 10)
            c.restoreState()
    elif kind == "pin":
        c.circle(12, 13, 8, stroke=1, fill=0)
        c.circle(12, 13, 2.2, stroke=1, fill=0)
        c.line(12, 5, 12, 1)
    c.restoreState()


def pill(label, x, top, width, fill=PALE, ink=PURPLE):
    rect(x, top, width, 20, fill, radius=10)
    centered(label, x, top + 6, width, 7.2, BOLD, ink)


def step(number, title, body, x, top, width):
    rect(x, top + 1, 20, 20, PURPLE, radius=10)
    centered(str(number), x, top + 7, 20, 8.5, BOLD, WHITE)
    text(title, x + 29, top + 2, 9.4, BOLD, INK)
    paragraph(body, x + 29, top + 18, width - 29, 7.5, 9.2, BODY, max_height=29)


def feature_card(title, kind, items, x, top, width, height):
    rect(x, top, width, height, WHITE, radius=12, stroke=LINE, line_width=0.75)
    rect(x + 11, top + 10, 26, 26, PALE, radius=8)
    icon(kind, x + 15, top + 14, 18)
    text(title.upper(), x + 45, top + 14, 8.4, BOLD, PURPLE_DARK)

    cursor = top + 43
    max_bottom = top + height - 8
    for item in items:
        c.setFillColor(PURPLE)
        c.circle(x + 15, H - cursor - 3.6, 1.55, stroke=0, fill=1)
        used = paragraph(item, x + 22, cursor, width - 33, 7.5, 9.0, BODY, max_height=29)
        cursor += used + 3.1
    card_checks.append({"title": title, "bottom": cursor, "limit": max_bottom})
    assert cursor <= max_bottom, (title, cursor, max_bottom)


# Page foundation and brand header.
rect(0, 0, W, H, PAPER)
rect(0, 0, W, 110, PALE_2)
image(ROOT / "design/onepager/assets/DaBin-logo.png", 32, 20, 111, 111 * 256 / 781)
pill("macOS 14+", W - 336, 24, 58)
pill("APPLE SILICON", W - 271, 24, 77)
pill("LOCAL FIRST", W - 187, 24, 59, MINT, MINT_INK)

text("Everything your day leaves behind, saved in one glance.", 32, 67, 23.5, BOLD, INK)
paragraph(
    "Drop it. Paste it. Find it later. DaBin turns the things you touch on your Mac into a private daily board.",
    33,
    96,
    640,
    9.3,
    12,
    BODY,
    max_height=14,
)
rect(W - 108, 17, 76, 76, PALE, radius=38)
image(ROOT / "native/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png", W - 103, 22, 66, 66)

# Three-step quick start.
rect(32, 124, W - 64, 58, WHITE, radius=12, stroke=LINE)
text("START HERE", 45, 141, 8.2, BOLD, PURPLE)
step(1, "Reveal", "Move to a corner, or choose the camera island home.", 129, 138, 192)
rule(328, 135, 328, 171)
step(2, "Feed DaBin", "Drop or paste into the robot or Daily window.", 343, 138, 192)
rule(542, 135, 542, 171)
step(3, "Open your day", "Double-click the robot, then browse Daily or Weekly.", 557, 138, 211)

text("EVERYTHING DABIN CAN DO", 32, 199, 8.2, BOLD, PURPLE)
right("Newest captures appear first", W - 32, 199, 7.7, NORMAL, MUTED)

LEFT = 32
GAP = 10
CARD_W = (W - 64 - 3 * GAP) / 4
CARD_H = 145
ROW_GAP = 10
GRID_TOP = 216

cards = [
    (
        "Capture anything",
        "capture",
        [
            "Drag or paste text, links, media, PDFs, documents, or files onto the robot or Daily.",
            "Hover the robot and press <b>Control-V</b> or <b>Command-V</b>; use <b>+</b> to create a task.",
            "Items added together share one card; previews fit and originals stay untouched.",
            "Stores time, type, source app, and source path when available.",
        ],
    ),
    (
        "Revisit your work",
        "calendar",
        [
            "First launch opens Daily; later, use the robot or menu bar to return.",
            "Daily has date navigation. Weekly ends on your selected date and hides empty days.",
            "Filter by <b>All, Text, Links, Files, Media,</b> or <b>Tasks</b>. Notifications gathers reminders.",
            "Move the board anywhere; DaBin remembers its position. Empty views show the bored robot.",
        ],
    ),
    (
        "Find anything",
        "search",
        [
            "Search the archive, a selected day, or the displayed week.",
            "Results open on the date with the same-day capture immediately before and after.",
            "Local recognition reads screenshots, images, PDFs, and supported text documents.",
            "Search also checks filenames, comments, and links. Copy recognized text or rebuild the index.",
        ],
    ),
    (
        "Work with each capture",
        "card",
        [
            "Copy original text, links, tasks, or saved files from the card; grouped files copy together.",
            "Add a comment or reminder, preview content, open the original, or reveal its saved folder.",
            "View and copy source details when available.",
            "Minimize, expand, or remove DaBin's saved card.",
        ],
    ),
    (
        "Tasks and reminders",
        "task",
        [
            "Create a task with <b>+</b>, or turn any capture into one without losing its content or date.",
            "Toggle red <b>Task</b> to green <b>Completed</b>.",
            "Open tasks without reminders carry forward at the top with their original creation date.",
            "Reminder tasks appear at the top only on their reminder day; macOS notifications are optional.",
        ],
    ),
    (
        "Copy or export",
        "export",
        [
            "Daily offers Copy Day or Export Text File; Weekly copies or downloads a chosen day or full week.",
            "Exports ignore filters, include every action, and sort chronologically.",
            "Includes time, type, source, text, captions, and recognized text when available.",
            "Copy and download output match; downloads use UTF-8 and clear date-based names.",
        ],
    ),
    (
        "Optional Auto Capture",
        "auto",
        [
            "Off by default. Saves only future clipboard changes and chosen-folder screenshots; never existing content.",
            "DaBin and common password managers are excluded by default. Pause or stop instantly; duplicates save once.",
            "Four automatic saves in one local clock hour form an expandable summary; success triggers the robot and burst count.",
        ],
    ),
    (
        "Robot, settings and menu bar",
        "settings",
        [
            "Corner or camera island home; the robot tracks, digests, and rotates through 12 success reactions.",
            "Dark mode, theme color, 35-100% opacity, Reduce Motion, and Reduce Transparency.",
            "Menu bar: Daily, status, pause or resume, Settings, and Quit. Direct builds add Get updates; Store builds update through Apple.",
        ],
    ),
]

for index, (title_value, kind, items) in enumerate(cards):
    row = index // 4
    column = index % 4
    x = LEFT + column * (CARD_W + GAP)
    top = GRID_TOP + row * (CARD_H + ROW_GAP)
    feature_card(title_value, kind, items, x, top, CARD_W, CARD_H)

# Privacy promise and footer.
FOOT_TOP = GRID_TOP + 2 * CARD_H + ROW_GAP + 12
rect(32, FOOT_TOP, W - 64, 43, PURPLE_DARK, radius=12)
icon("pin", 44, FOOT_TOP + 12, 18, WHITE)
text("PRIVATE AND LOCAL", 71, FOOT_TOP + 9, 8.3, BOLD, WHITE)
paragraph(
    "Readable Year / Month / Day folders on this Mac. No account, analytics, ads, cloud sync, external AI, or automatic uploads. Link previews connect only when you enable them; Quit stops every background activity.",
    71,
    FOOT_TOP + 22,
    W - 117,
    7.5,
    9.1,
    colors.HexColor("#F7F1FA"),
    max_height=20,
)

text("DaBin", 32, 574, 7.7, BOLD, PURPLE)
right("Keys: Command-O Today  |  Command-K Search  |  Command-Shift-V robot  |  Esc hide  |  Command-Q quit", W - 32, 574, 7.4, NORMAL, MUTED)

c.showPage()
c.save()
copy2(OUT, DOC_COPY)

# Structural and content checks stay with the generator so future edits cannot
# silently turn this one-pager into a multi-page or incomplete guide.
reader = PdfReader(OUT)
assert len(reader.pages) == 1
page = reader.pages[0]
media_box = tuple(round(float(value), 2) for value in page.mediabox)
assert media_box == (0.0, 0.0, round(W, 2), round(H, 2)), media_box
extracted = page.extract_text()
normalized = " ".join(extracted.split())

required = [
    "Capture anything",
    "Daily",
    "Weekly",
    "All, Text, Links, Files, Media, or Tasks",
    "Search the archive",
    "Local recognition",
    "same-day capture immediately before and after",
    "Add a comment or reminder",
    "source path",
    "Minimize, expand, or remove",
    "turn any capture into one",
    "Completed",
    "carry forward",
    "Copy or export",
    "full week",
    "ignore filters",
    "UTF-8",
    "Auto Capture",
    "Off by default",
    "common password managers are excluded by default",
    "Four automatic saves in one local clock hour",
    "expandable summary",
    "12 success reactions",
    "dark mode",
    "35-100% opacity",
    "Get updates",
    "Store builds update through Apple",
    "APPLE SILICON",
    "Readable Year / Month / Day folders",
    "No account, analytics, ads, cloud sync, external AI, or automatic uploads",
]
for phrase in required:
    assert phrase.lower() in normalized.lower(), phrase
assert "\ufffd" not in extracted
assert all(block["x"] >= 28 and block["x"] + block["width"] <= W - 28 for block in text_blocks)
assert all(block["top"] + block["height"] < H - 11 for block in text_blocks)
assert OUT.read_bytes() == DOC_COPY.read_bytes()

QA_PATH.write_text(
    json.dumps(
        {
            "page_count": len(reader.pages),
            "page_size": "A4 landscape",
            "media_box": media_box,
            "word_count": len(extracted.split()),
            "cards": card_checks,
            "paragraphs": text_blocks,
            "required_phrases": required,
            "text": extracted,
        },
        indent=2,
    )
)
print(OUT)
print(DOC_COPY)
print(f"PASS: one A4 page, {len(extracted.split())} words, complete feature checklist, matching copies")
