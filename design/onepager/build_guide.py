"""Build the friendly, robot-led guide from native UI renders and shared copy."""
from pathlib import Path
from shutil import copy2
from html import escape
import hashlib
import json

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design/onepager"
ASSETS = DESIGN / "assets"
COPY = json.loads((DESIGN / "copy.json").read_text())
OUT = ROOT / "output/pdf/DaBin-Quick-Guide.pdf"
DOC_COPY = ROOT / "docs/DaBin-Quick-Guide.pdf"
COPY_OUT = ROOT / "output/copy/DaBin-Friendly-Copy.txt"
QA_PATH = ROOT / "tmp/pdfs/robot-guide-layout-check.json"
MANIFEST = ASSETS / "guide-assets.json"

INK = colors.HexColor("#30283D")
BODY = colors.HexColor("#625B6A")
PURPLE = colors.HexColor("#72508E")
PURPLE_DARK = colors.HexColor("#4A365C")
PALE = colors.HexColor("#F2EDF6")
PAPER = colors.HexColor("#FCFAFD")
LINE = colors.HexColor("#E1D8E8")
MINT = colors.HexColor("#E5F3EF")
TEAL = colors.HexColor("#257A70")
WHITE = colors.white
W, H = landscape(A4)
NORMAL, BOLD = "DaBinSans", "DaBinSans-Bold"
FONT_FILES = {
    NORMAL: Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    BOLD: Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf"),
}
for name, source in FONT_FILES.items():
    pdfmetrics.registerFont(TTFont(name, str(source)))

required_assets = ["DABIN__GUIDE__PROJECTS.png", "DABIN__GUIDE__INBOX.png",
                   "DABIN__GUIDE__TASK.png", "DABIN__GUIDE__ROBOT.png"]
for name in required_assets:
    if not (ASSETS / name).is_file():
        raise FileNotFoundError(f"Run export_guide_assets.py first: {name}")
assets = json.loads(MANIFEST.read_text())
native_provenance = json.loads((ASSETS / assets["native_source_manifest"]).read_text())
for name in required_assets:
    assert hashlib.sha256((ASSETS / name).read_bytes()).hexdigest() == native_provenance["assetsSHA256"][name], name
assert hashlib.sha256((DESIGN / "ExportGuide.swift").read_bytes()).hexdigest() == native_provenance["exportSourceSHA256"]
for name, digest in native_provenance["sourceSHA256"].items():
    assert hashlib.sha256((ROOT / "native" / name).read_bytes()).hexdigest() == digest, f"Re-export stale native guide UI: {name}"
for folder in [OUT.parent, COPY_OUT.parent, QA_PATH.parent]:
    folder.mkdir(parents=True, exist_ok=True)

# Preserve the previous delivered PDF before replacing either stable copy.
for previous in [DOC_COPY, OUT]:
    if previous.is_file():
        digest = hashlib.sha256(previous.read_bytes()).hexdigest()[:12]
        archive = DESIGN / "archive" / f"DaBin-Quick-Guide__before_robot_walkthrough__{digest}.pdf"
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            copy2(previous, archive)

c = canvas.Canvas(str(OUT), pagesize=(W, H), pageCompression=1)
c.setTitle("DaBin | A friendly robot-led quick guide")
c.setAuthor("DaBin")
c.setSubject("Save, organize and return to your work with DaBin")
c.setCreator("DaBin robot-led guide, native UI fixtures")
blocks, images, annotations = [], [], []
page = 1


def rect(x, top, width, height, fill, radius=0, stroke=None):
    c.setFillColor(fill)
    c.setStrokeColor(stroke or fill)
    c.setLineWidth(0.75)
    c.roundRect(x, H - top - height, width, height, radius,
                stroke=int(stroke is not None), fill=1)


def paragraph(value, x, top, width, size=11, leading=15, color=BODY,
              font=NORMAL, max_height=None):
    style = ParagraphStyle("guide", fontName=font, fontSize=size, leading=leading,
                           textColor=color, allowWidows=0, allowOrphans=0)
    p = Paragraph(value, style)
    _, height = p.wrap(width, H)
    if max_height is not None:
        assert height <= max_height, (value, height, max_height)
    p.drawOn(c, x, H - top - height)
    blocks.append(dict(page=page, text=value, x=x, top=top, width=width,
                       height=height, font_size=size))
    return height


def label(value, x, top, size=9, color=PURPLE, font=BOLD):
    return paragraph(escape(value), x, top, W - x - 30, size, size * 1.25, color, font)


def image_contain(name, x, top, width, height):
    source = ImageReader(str(ASSETS / name))
    sw, sh = source.getSize()
    scale = min(width / sw, height / sh)
    iw, ih = sw * scale, sh * scale
    ix, it = x + (width - iw) / 2, top + (height - ih) / 2
    c.drawImage(source, ix, H - it - ih, width=iw, height=ih, mask="auto")
    images.append(dict(page=page, asset=name, x=ix, top=it, width=iw, height=ih))
    return ix, it, iw, ih


def image_crop(name, x, top, width, height, crop):
    """Crop by PDF clipping only; the native source PNG remains unmodified."""
    source = ImageReader(str(ASSETS / name))
    sw, sh = source.getSize()
    left, upper, right, lower = crop
    cw, ch = sw * (right - left), sh * (lower - upper)
    scale = min(width / cw, height / ch)
    iw, ih = cw * scale, ch * scale
    ix, it = x + (width - iw) / 2, top + (height - ih) / 2
    c.saveState()
    clip = c.beginPath()
    clip.roundRect(ix, H - it - ih, iw, ih, 8)
    c.clipPath(clip, stroke=0, fill=0)
    c.drawImage(source, ix - sw * left * scale,
                H - it + sh * upper * scale - sh * scale,
                width=sw * scale, height=sh * scale, mask="auto")
    c.restoreState()
    images.append(dict(page=page, asset=name, x=ix, top=it, width=iw, height=ih,
                       source_crop=crop))


def badge(number, x, top, radius=10, fill=PURPLE):
    c.setFillColor(fill)
    c.setStrokeColor(WHITE)
    c.setLineWidth(2)
    c.circle(x, H - top, radius, stroke=1, fill=1)
    c.setFont(BOLD, 10)
    c.setFillColor(WHITE)
    c.drawCentredString(x, H - top - 3.4, str(number))


def bubble(value, x, top, width, height):
    rect(x, top, width, height, PURPLE_DARK, 12)
    c.setFillColor(PURPLE_DARK)
    tail = c.beginPath()
    tail.moveTo(x, H - top - 22)
    tail.lineTo(x - 10, H - top - 31)
    tail.lineTo(x, H - top - 37)
    tail.close()
    c.drawPath(tail, stroke=0, fill=1)
    paragraph(escape(value), x + 12, top + 12, width - 24, 12, 15, WHITE,
              BOLD, max_height=height - 20)


def footer(number, note="Real interface. Fictional examples."):
    c.setStrokeColor(LINE)
    c.setLineWidth(0.7)
    c.line(36, 31, W - 36, 31)
    paragraph(f"DaBin {COPY['version']}  |  {escape(note)}", 36, H - 23,
              W - 95, 8.4, 10, BODY)
    paragraph(str(number), W - 48, H - 23, 12, 8.4, 10, PURPLE, BOLD)


def page_header(section):
    rect(0, 0, W, H, PAPER)
    label(section["eyebrow"], 36, 25, 8.6)
    label(section["title"], 36, 44, 30, INK)


# 1: the robot explains the interface using the exact native project view.
p1 = COPY["page_one"]
page_header(p1)
paragraph(escape(p1["intro"]), 36, 84, W - 72, 12.5, 17, BODY, max_height=34)
paragraph(escape(p1["quick_start"]), 36, 126, W - 72, 10.5, 14, PURPLE_DARK, max_height=16)
rect(36, 151, 193, 83, PALE, 16)
image_contain("DABIN__GUIDE__ROBOT.png", 46, 155, 67, 75)
bubble(p1["robot_bubble"], 126, 157, 91, 66)

for item, top in zip(p1["callouts"], [248, 322, 394, 466]):
    badge(item["number"], 47, top + 8, 10, TEAL if item["number"] == 1 else PURPLE)
    paragraph(escape(item["title"]), 65, top, 164, 11.2, 14, INK, BOLD, max_height=28)
    paragraph(escape(item["body"]), 36, top + 24, 193, 10.5, 13.5, BODY, max_height=68)

hero = image_contain("DABIN__GUIDE__PROJECTS.png", 249, 151, W - 285, 403)
hx, ht, hw, hh = hero
for number, anchor in assets["project_callout_anchors"].items():
    ax, ay = anchor
    bx, bt = hx + ax * hw, ht + ay * hh
    tx, ty = assets["project_callout_targets"][number]
    c.setStrokeColor(TEAL if number == "1" else PURPLE)
    c.setLineWidth(0.65)
    c.line(bx, H - bt, hx + tx * hw, H - ht - ty * hh)
    badge(int(number), bx, bt, 10, TEAL if number == "1" else PURPLE)
    annotations.append(dict(number=int(number), x=bx, top=bt,
                            normalized_native_anchor=[ax, ay]))
footer(1)
c.showPage()

# 2: three clear habits, each paired with a relevant real interface excerpt.
page = 2
p2 = COPY["page_two"]
page_header(p2)
paragraph(escape(p2["subtitle"]), 36, 86, W - 72, 12, 16, BODY, max_height=18)
gap = 14
card_width = (W - 72 - 2 * gap) / 3
step_assets = ["DABIN__GUIDE__INBOX.png", "DABIN__GUIDE__PROJECTS.png", "DABIN__GUIDE__TASK.png"]
for index, step in enumerate(p2["steps"]):
    x = 36 + index * (card_width + gap)
    rect(x, 123, card_width, 315, WHITE, 15, LINE)
    badge(step["number"], x + 21, 144, 10)
    paragraph(escape(step["title"]), x + 40, 135, card_width - 52, 12.3, 15,
              INK, BOLD, max_height=30)
    name = step_assets[index]
    image_crop(name, x + 12, 175, card_width - 24, 131, assets["step_crops"][name])
    used = paragraph(escape(step["body"]), x + 14, 322, card_width - 28, 10.7,
                     14, BODY, max_height=70)
    paragraph(escape(step["tip"]), x + 14, 322 + used + 10, card_width - 28,
              10.2, 13, PURPLE_DARK, max_height=65)

rect(36, 454, 474, 103, MINT, 14)
paragraph(escape(p2["auto_title"]), 50, 465, 445, 12, 15, TEAL, BOLD, max_height=18)
paragraph(escape(p2["auto_body"]), 50, 488, 445, 10.3, 13.2, BODY, max_height=40)
paragraph(escape(p2["auto_tip"]), 50, 529, 445, 10.1, 12.8, TEAL, max_height=27)
rect(524, 454, W - 560, 103, PALE, 14)
paragraph(escape(p2["comfort_title"]), 538, 465, W - 588, 12, 15,
          PURPLE_DARK, BOLD, max_height=18)
paragraph(escape(p2["comfort_body"]), 538, 489, W - 588, 10.3, 13.2,
          BODY, max_height=65)
footer(2, "Saved on your Mac. No account or cloud sync.")
c.showPage()
c.save()

# A reusable text version shares the PDF's copy source rather than drifting.
copy_lines = ["DABIN - FRIENDLY PRODUCT COPY", "", COPY["headline"], "", COPY["description"], "",
              "ROBOT-LED QUICK GUIDE", "", p1["title"], p1["intro"], "", p1["meet_title"],
              p1["meet_body"], p1["island_note"], ""]
for item in p1["callouts"]:
    copy_lines += [item["title"], item["body"], ""]
copy_lines += [p2["title"], p2["subtitle"], ""]
for step in p2["steps"]:
    copy_lines += [step["title"], step["body"], step["tip"], ""]
copy_lines += [p2["auto_title"], p2["auto_body"], p2["auto_tip"], "",
               p2["comfort_title"], p2["comfort_body"], "", p2["privacy_title"], p2["privacy_body"], ""]
COPY_OUT.write_text("\n".join(copy_lines), encoding="utf-8")

reader = PdfReader(OUT)
assert len(reader.pages) == 2
extracted = "\n".join(p.extract_text() for p in reader.pages)
searchable_text = " ".join(extracted.split()).lower()
assert "\ufffd" not in extracted
required = ["Hi, I'm DaBin.", "Choose a project", "Inbox", "Today", "Projects", "Explorer",
            "Find it again", "Save now. Sort later.", "Auto Capture", "off by default",
            "Only new changes are saved", "task stays open", "Show tooltips"]
for phrase in required:
    assert phrase.lower() in searchable_text, phrase
for block in blocks:
    assert block["x"] >= 30 and block["x"] + block["width"] <= W - 28, block
    assert block["top"] + block["height"] <= H - 9, block
for item in images:
    assert item["x"] >= 30 and item["x"] + item["width"] <= W - 28, item
    assert item["top"] + item["height"] <= H - 30, item
copy2(OUT, DOC_COPY)
assert OUT.read_bytes() == DOC_COPY.read_bytes()
QA_PATH.write_text(json.dumps(dict(
    page_count=2, page_size="A4 landscape", word_count=len(extracted.split()),
    paragraphs=blocks, images=images, native_annotations=annotations,
    pdf_sha256=hashlib.sha256(OUT.read_bytes()).hexdigest(),
    copy_source_sha256=hashlib.sha256((DESIGN / "copy.json").read_bytes()).hexdigest(),
    native_asset_manifest=str(MANIFEST.relative_to(ROOT)),
    embedded_fonts={name: str(path) for name, path in FONT_FILES.items()},
    native_asset_hash_check="PASS",
    current_native_source_hash_check="PASS",
    copy_output_sha256=hashlib.sha256(COPY_OUT.read_bytes()).hexdigest(),
    required_phrases=required, text=extracted,
    privacy="Actual native views with isolated fictional examples; no personal capture screenshots.",
    visual_review="Pending Poppler rendering and manual review."
), indent=2), encoding="utf-8")
print(OUT)
print(COPY_OUT)
print(f"PASS: two A4 landscape pages, {len(extracted.split())} words, matching PDF copies; render before delivery")
