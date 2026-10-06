#!/usr/bin/env python3
"""Build a local, reviewable submission document from verified release copy."""
import argparse
from datetime import date
import hashlib
import json
import re
import shutil
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT, WD_SECTION_START
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor
from PIL import Image

from release_inputs import ROOT, add_release_arguments, read_release, verify_asset_manifest, verify_unchanged

parser = argparse.ArgumentParser(description=__doc__)
add_release_arguments(parser)
parser.add_argument('--build-docx', action='store_true', required=True, help='Author after the artifact marker and screenshot review')
parser.add_argument('--metadata-file', type=Path, default=ROOT / 'docs/app-store/metadata-en-US.json')
parser.add_argument('--screenshots-dir', type=Path)
parser.add_argument('--output-dir', type=Path)
parser.add_argument('--prepared-date', default=date.today().strftime('%-d %B %Y'))
parser.add_argument('--apple-audit-date', default='5 October 2026', help='Date the referenced Apple sources were actually checked')
parser.add_argument('--qa-report', help='Current coordinated release QA report path relative to project root')
parser.add_argument('--qa-status', choices=['pending', 'failed', 'passed'], default='pending')
parser.add_argument('--qa-summary', help='Actual result or remaining checks; no inferred success')
parser.add_argument('--performance-status', choices=['pending', 'failed', 'passed'], default='pending')
parser.add_argument('--performance-summary', help='Actual measurements and unmet budgets, or pending acceptance')
parser.add_argument('--known-issue', action='append', default=[], help='Unresolved issue to include in this review draft')
parser.add_argument('--replace-draft', action='store_true', help='Replace this candidate draft during render repair only')
args = parser.parse_args()
qa_evidence = (ROOT / args.qa_report).resolve() if args.qa_report else None
if (args.qa_status == 'passed' or args.performance_status == 'passed') and (qa_evidence is None or not qa_evidence.is_file()):
    raise SystemExit('An existing current QA evidence file is required for any passed status.')
if args.qa_status == 'failed' and not args.qa_summary:
    raise SystemExit('A failed QA status requires an actual --qa-summary.')
if args.performance_status == 'failed' and not args.performance_summary:
    raise SystemExit('A failed performance status requires an actual --performance-summary.')
release = read_release(args)
VERSION, BUILD, PREPARED_DATE = release['version'], release['build'], args.prepared_date
NATIVE = release['native']
META = json.loads(args.metadata_file.read_text())
if (META['candidate']['version'], META['candidate']['build']) != (VERSION, BUILD):
    raise SystemExit('Metadata candidate must match selected native inputs.')
SCREENSHOTS = (args.screenshots_dir or ROOT / f'docs/app-store/screenshots/{VERSION}-{BUILD}').resolve()
MANIFEST = json.loads((SCREENSHOTS / 'manifest.json').read_text())
verify_asset_manifest(MANIFEST, release)
if not str(MANIFEST.get('visualReview', '')).startswith('PASS'):
    raise SystemExit('Inspect every screenshot and record its visual PASS before authoring the content document.')
OUT = (args.output_dir or ROOT / f'docs/app-store/submission-pack-{VERSION}-{BUILD}').resolve()
if OUT.exists() and any(OUT.iterdir()) and not args.replace_draft:
    raise SystemExit('Output is not empty. Preserve prior packs or explicitly replace only this candidate draft.')
if OUT.name.startswith('submission-pack-') and OUT.name != f'submission-pack-{VERSION}-{BUILD}':
    raise SystemExit('The historical submission pack must remain unchanged.')
OUT.mkdir(parents=True, exist_ok=True)
COPY = OUT / 'Copy'
COPY.mkdir(exist_ok=True)
SHOTS = OUT / 'Screenshots'
SHOTS.mkdir(exist_ok=True)
ASSETS = OUT / 'Assets'
ASSETS.mkdir(exist_ok=True)
shutil.copy2(NATIVE / 'Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png', ASSETS / 'DaBin-App-Icon-1024.png')
shutil.copy2(NATIVE / 'Resources/AppIcon.icns', ASSETS / 'AppIcon.icns')
P = META['productPage']
for shot in MANIFEST['screenshots']:
    source = SCREENSHOTS / shot['file']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == shot['sha256']
    im = Image.open(source)
    assert im.size == (1440, 900) and im.mode == 'RGB'
    shutil.copy2(source, SHOTS / source.name)

WHATS_NEW = ('The little DaBin companion peeks out as you approach and opens with one click. Successful automatic saves bring a nod, wiggle or sign raise, with rapid saves sharing an item count. Quiet mode and Reduce Motion use a still expression. Captions, Tasks and Projects have compact controls; project dates can be picked by day or week, and Export Selected saves only the items you check.')
SUPPORT = [
    ('Contact support', 'Email: [PUBLIC SUPPORT EMAIL]\nSupport page: [PUBLIC SUPPORT URL]\nInclude your DaBin version, macOS version and the steps that led to the issue. Use fictional examples and remove private material from any screenshots. Do not send your capture archive, passwords or sensitive clipboard contents.'),
    ('Getting started', 'Open DaBin from its menu-bar item or click the revealed desktop robot once. Paste text or a link into Captions, or drop in a file. Use the upper + button to create a task directly. Keep related work in a project and use Search to find it again.'),
    ('What does Search cover', 'Search finds content saved into DaBin, across projects and dates. You can type, use the context-menu Paste action or press Command-V in the search field. Results appear in date columns. Local text recognition also indexes supported saved images and documents; it does not search every file on your Mac.'),
    ('Does Auto Capture record my screen', 'No. Auto Capture is optional and starts off. After you enable it, DaBin can save later clipboard changes and new images added to the screenshot folder you choose. Existing clipboard contents and existing images are not imported when monitoring starts. The red menu-bar symbol indicates active monitoring. Pause or switch it off whenever you need to.'),
    ('Where is my content stored', 'On this Mac. DaBin has no account, cloud sync, advertising or analytics. Optional website previews are off by default and can contact websites for manually saved links. Automatic captures never fetch link previews. Exports and backups are stored in the location you choose; a cloud-synced destination may upload them through that service.'),
    ('How do I move content to another app', 'Drag a card or caption to a destination that accepts its text, link, image or file representation. The receiving app controls what it can accept. You can also copy and paste or export. DaBin keeps its saved content, and original source files remain in place.'),
    ('How do I export a project selection', 'In Projects, check the items you want and choose Export Selected. DaBin creates a ZIP containing those selected items at the destination you choose. The day/week date picker and filters help narrow the workspace; selecting a date or filter alone does not select items for export.'),
    ('How does the companion respond', 'With Auto Capture off, approach the chosen corner or camera island to reveal the companion. Click once to open DaBin, including during movement. Successful automatic saves use generic acknowledgements; rapid saves can share an item count. Quiet mode and Reduce Motion keep the expression still. Paused capture remains clearly labeled.'),
    ('How do I back up or remove content', 'Use More > Back up archive to create a local backup. Recently Deleted lets you restore removed captures or delete them permanently. Turning Auto Capture off stops new monitoring but keeps earlier captures. See Settings > Privacy policy & data controls for complete deletion instructions.'),
    ('Which Macs are supported', f'DaBin {VERSION} requires an Apple Silicon Mac with macOS 14 or later. The Mac App Store version receives updates through the App Store.'),
]

PUBLIC_FIELDS = {'Name':P['name'], 'Subtitle':P['subtitle'], 'Promotional text':P['promotionalText'],
                 'Description':P['description'], 'Keywords':P['keywords'],
                 'Whats New for a subsequent App Store version only':WHATS_NEW}
for label, content in PUBLIC_FIELDS.items():
    filename = re.sub(r'[^a-z0-9]+', '-', label.lower()).strip('-') + '.txt'
    (COPY / filename).write_text(content + '\n')
(COPY / 'review-notes.txt').write_text(META['review']['notes'] + '\n')
(COPY / 'support-page.txt').write_text('DaBin support\n\n' + '\n\n'.join(h+'\n'+b for h,b in SUPPORT) + '\n\nPrivacy policy\n'+P['privacyPolicyURL']+'\n')
(COPY / 'metadata-en-US.json').write_bytes(args.metadata_file.read_bytes())
POLICY = NATIVE / 'Resources/PrivacyPolicy.md'
POLICY_DATE = next((line.removeprefix('Updated ') for line in POLICY.read_text().splitlines() if line.startswith('Updated ')), 'the final bundled policy')
shutil.copy2(POLICY, COPY / 'PrivacyPolicy.md')

doc = Document()
doc.core_properties.title = 'DaBin App Store Content'
doc.core_properties.subject = f'Mac App Store submission content for DaBin {VERSION} build {BUILD}'
doc.core_properties.author = 'DaBin'
doc.core_properties.keywords = 'DaBin, Mac App Store, listing, screenshots, privacy'
doc.core_properties.comments = ''
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.27), Inches(11.69)
section.top_margin = section.bottom_margin = Inches(.62)
section.left_margin = section.right_margin = Inches(.72)
section.footer_distance = Inches(.25)
for name in ['Normal', 'Title', 'Subtitle', 'Heading 1', 'Heading 2', 'Heading 3', 'Caption']:
    st = doc.styles[name]
    st.font.name = 'Arial'
    st.font.color.rgb = RGBColor(0,0,0)
    st.font.size = Pt(10.5)
    st.paragraph_format.space_after = Pt(7)
    st.paragraph_format.line_spacing = 1.1
for name,size in [('Title',29),('Subtitle',12),('Heading 1',20),('Heading 2',13),('Heading 3',11)]:
    st=doc.styles[name]
    st.font.size=Pt(size)
    st.font.bold=name!='Subtitle'
    st.paragraph_format.space_before=Pt(12 if name.startswith('Heading') else 0)
    st.paragraph_format.space_after=Pt(7)
doc.styles['Caption'].font.size=Pt(9)
doc.styles['Caption'].font.italic=False
for st in doc.styles:
    for border in list(st.element.iter(qn('w:pBdr'))):
        border.getparent().remove(border)
    if st.type == 1:
        st.font.underline=False
footer = section.footer.paragraphs[0]
footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
footer.add_run(f'DaBin {VERSION}  |  ')
field = OxmlElement('w:fldSimple'); field.set(qn('w:instr'), 'PAGE'); footer._p.append(field)
for r in footer.runs: r.font.size=Pt(8); r.font.color.rgb=RGBColor.from_string('444444')

def p(text='', style=None, bold=False):
    para=doc.add_paragraph(style=style)
    run=para.add_run(text); run.bold=bold
    return para

def h(text, level=1): return doc.add_heading(text, level)
def page(title):
    para=h(title)
    para.paragraph_format.page_break_before=True
    return para

def table(headers, rows, widths):
    t=doc.add_table(rows=1, cols=len(headers)); t.alignment=WD_TABLE_ALIGNMENT.CENTER; t.autofit=False
    for c,w in zip(t.columns,widths): c.width=Inches(w)
    for c,txt in zip(t.rows[0].cells,headers): c.text=txt
    for row in rows:
        cells=t.add_row().cells
        for c,txt in zip(cells,row): c.text=str(txt)
    tblpr=t._tbl.tblPr
    borders=OxmlElement('w:tblBorders')
    for edge in ['top','left','bottom','right','insideH','insideV']:
        e=OxmlElement('w:'+edge); e.set(qn('w:val'),'single');e.set(qn('w:sz'),'4');e.set(qn('w:color'),'D9D9D9');borders.append(e)
    tblpr.append(borders)
    for i,row in enumerate(t.rows):
        trpr=row._tr.get_or_add_trPr(); cant=OxmlElement('w:cantSplit');trpr.append(cant)
        if i==0:
            repeat=OxmlElement('w:tblHeader');trpr.append(repeat)
        for j,c in enumerate(row.cells):
            c.width=Inches(widths[j]);c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
            pr=c._tc.get_or_add_tcPr()
            sh=OxmlElement('w:shd');sh.set(qn('w:fill'),'263644' if i==0 else ('F3F6F8' if i%2 else 'FFFFFF'));pr.append(sh)
            margins=OxmlElement('w:tcMar')
            for edge in ['top','left','bottom','right']:
                v=OxmlElement('w:'+edge);v.set(qn('w:w'),'85');v.set(qn('w:type'),'dxa');margins.append(v)
            pr.append(margins)
            for para in c.paragraphs:
                para.paragraph_format.space_after=Pt(1);para.paragraph_format.space_before=Pt(1)
                para.paragraph_format.line_spacing=1.04
                for run in para.runs:
                    run.font.size=Pt(9.5);run.font.bold=i==0
                    run.font.color.rgb=RGBColor.from_string('FFFFFF' if i==0 else '000000')
    p('').paragraph_format.space_after=Pt(0)
    return t

def link(label,url):
    para=doc.add_paragraph()
    a=OxmlElement('w:hyperlink');a.set(qn('r:id'),doc.part.relate_to(url,'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',is_external=True))
    r=OxmlElement('w:r');pr=OxmlElement('w:rPr');color=OxmlElement('w:color');color.set(qn('w:val'),'155E69');pr.append(color);r.append(pr)
    tx=OxmlElement('w:t');tx.text=label;r.append(tx);a.append(r);para._p.append(a)
    para.paragraph_format.space_after=Pt(5)
    return para

p('DaBin App Store Content', 'Title')
p(f'Version {VERSION.replace(chr(46), chr(32))}   Build {BUILD}   English US   {PREPARED_DATE}', 'Subtitle')
p('Use this document to populate DaBin’s Mac App Store listing, prepare the review submission and publish the supporting privacy and support content. The screenshot pages show the current native interface; the accompanying folder contains the original upload images and plain text fields.')
p('This local review draft is not ready for submission while quality, performance or release gates remain open. Complete the owner fields and release checks before submission. Copy only the text under the relevant field into App Store Connect. Reviewer notes are private; listing copy, support details and the privacy policy are public.')
h('App information')
table(['Field','Value','Status'],[
('Platform','macOS','Prepared'),('App name','DaBin','Name availability to confirm'),('Subtitle',P['subtitle'],f"{len(P['subtitle'])} of 30 characters"),
('Primary category','Productivity','Proposed'),('Primary language','English US','Proposed'),('Bundle ID','com.dabin.mac','Confirm Connect record'),
('Version and build',f'{VERSION}  /  {BUILD}','Confirm build availability'),('Requirements','Apple Silicon  /  macOS 14 or later','Current build'),
('SKU','[OWNER APP SKU]','Private app record field'),('Secondary category','None proposed','Optional')], [1.55,3.15,2.13])
h('Promotional text',2);p(P['promotionalText']);p(f"{len(P['promotionalText'])} of 170 characters. Public product page field.", 'Caption')
h('Keywords',2);p(P['keywords']);p(f"{len(P['keywords'].encode('utf-8'))} of 100 bytes. Paste as one comma-separated line.", 'Caption')

page('Product description')
p(f"Public Description field  |  {len(P['description'])} of 4000 characters", 'Caption')
for block in P['description'].split('\n\n'):
    if '\n' in block:
        title,body=block.split('\n',1);h(title,2);p(body)
    else:p(block)
h('Whats New for an update',2)
p('Use this field only for a subsequent App Store version. Apple does not offer it for a first App Store version.','Caption')
p(WHATS_NEW)

page('App Review notes')
p('Private App Review Information  |  No sign in required  |  No demo credentials','Caption')
for block in META['review']['notes'].split('\n\n'):
    p(block)
p('2531 of 4000 bytes. Enter the real review contact separately on the owner details page. The Quick Guide PDF can be attached as supplemental review material if useful.','Caption')

land=doc.add_section(WD_SECTION_START.NEW_PAGE)
land.orientation=WD_ORIENT.LANDSCAPE
land.page_width,land.page_height=Inches(11.69), Inches(8.27)
land.top_margin=land.bottom_margin=Inches(.45)
land.left_margin=land.right_margin=Inches(.65)
shots=[
('Screenshot 1 Captions','DABIN__APP_STORE__01_INBOX.png','Keep the useful bits.','Save notes, images and files. Sort them when you’re ready.'),
('Screenshot 2 Projects','DABIN__APP_STORE__02_PROJECTS.png','A home for every project.','Choose a color. Keep your previews, notes and tasks together.'),
('Screenshot 3 Focus','DABIN__APP_STORE__03_FOCUS.png','Make room for one task.','Choose a duration and start a focus timer when you’re ready.')]
for i,(title,filename,headline,subline) in enumerate(shots):
    if i: doc.add_page_break()
    ph=h(title);ph.paragraph_format.space_before=Pt(0);ph.paragraph_format.space_after=Pt(4)
    para=doc.add_paragraph();para.paragraph_format.space_after=Pt(4)
    picture=para.add_run().add_picture(str(SHOTS/filename),width=Inches(9.7))
    picture._inline.docPr.set('descr',f'{headline} {subline} Native DaBin view with fictional content.')
    p(f'{filename}  |  1440 × 900  |  RGB PNG  |  No transparency','Caption')
    p('Upload the original PNG from Screenshots in this order. Compare against the final signed app and confirm artwork rights before upload.','Caption')

portrait=doc.add_section(WD_SECTION_START.NEW_PAGE)
portrait.orientation=WD_ORIENT.PORTRAIT
portrait.page_width,portrait.page_height=Inches(8.27), Inches(11.69)
portrait.top_margin=portrait.bottom_margin=Inches(.62)
portrait.left_margin=portrait.right_margin=Inches(.72)
h('Privacy and declarations')
p('Confirm these answers against the exact distribution-signed build and the current App Store Connect questionnaires. These are proposed answers supported by the current source audit, not completed account declarations.')
table(['Declaration','Prepared answer or required decision'],[
('App Privacy','Data Not Collected is proposed. Saved captures, notes, recognized text and usage remain on device; the developer receives none of them. Owner confirmation is required.'),
('Tracking','No tracking in the audited source. No advertising or analytics SDK was found.'),
('Optional networking','Website previews are off by default. Enabling them can send URLs and connection data to websites for manually saved links. Automatic links never fetch previews. Review this behavior when completing privacy answers.'),
('Privacy URL',f'Use the linked policy below after publishing the {POLICY_DATE} text and verifying that the public and bundled versions match.'),
('Age rating','Complete Apple’s current questionnaire. No numeric rating is assigned in this pack; assess actual features and optional website access.'),
('Export compliance','Uses non-exempt encryption: false is proposed in the current metadata. The audited implementation uses system HTTPS. Owner must confirm the current questionnaire and any regional documentation.'),
('Content rights','Questionnaire: [OWNER ANSWER]. Confirm permission for third-party content displayed or accessed, including optional website previews. Also confirm rights to the app, name, robot, icon and screenshot artwork. Local storage does not determine the rights answer.'),
('Accessibility labels','Optional declarations. Claim only features evaluated against Apple’s criteria in the exact signed app. No label is claimed by this pack.'),
('License agreement','Apple’s standard agreement is a proposed default. Owner must select it or provide a reviewed custom agreement.')], [1.55,5.28])
link('Privacy policy destination',P['privacyPolicyURL'])
h('Permissions and behavior for review',2)
p('Auto Capture starts off and uses explicit opt-in. Screenshot monitoring uses a folder chosen in the macOS picker. Reminder notifications are requested when a reminder is saved. DaBin does not request Accessibility, Screen Recording, camera or microphone access. Mac App Store builds use the sandbox and App Store updates; the direct-download updater is excluded.')

page('Owner details and release checks')
p('Fill these fields in a private copy. Review contact details belong in App Store Connect and must not be placed in the public support page or a public repository.')
table(['Field','Owner response'],[
('Connect record','[APPLE ID]  /  [DEVELOPER DISPLAY NAME]'),('Legal rights holder','[LEGAL NAME]'),('Copyright field','2026 [LEGAL RIGHTS HOLDER]'),('Public support email','[PUBLIC SUPPORT EMAIL]'),('Public support URL','[MAINTAINED PUBLIC SUPPORT URL]'),
('Private review contact','[FIRST NAME] [LAST NAME]'),('Private review email','[REVIEW EMAIL]'),('Private review phone','[PHONE WITH COUNTRY CODE]'),
('Price and tax category','[PRICE]  /  [TAX CATEGORY]'),('Countries and regions','[AVAILABILITY]'),('Release method','[MANUAL OR AUTOMATIC RELEASE]'),
('EU trader declaration','[TRADER STATUS AND REQUIRED VERIFIED DETAILS]'),('Optional public URLs','[MARKETING]  /  [PRIVACY CHOICES]  /  [ACCESSIBILITY]')], [2.3,4.53])
h('Release status',2)
p(f"Native QA: {args.qa_status}. {args.qa_summary or 'Current candidate acceptance is pending; earlier-source results do not establish this candidate’s stability.'}")
p(f"Performance: {args.performance_status}. {args.performance_summary or 'Strict interaction and zoom performance acceptance remains pending for the selected candidate.'}")
for issue in args.known_issue:
    p(issue, style='List Bullet')
p('A hash-verified production module proves matching compiled inputs. It does not prove that every runtime suite passed, that performance budgets were met, or that distribution signing and Apple review are complete.')
h('Before submitting',2)
for text in [
    'Confirm the app record, name availability, SKU, developer display name, bundle ID and version/build number. Complete current agreements and applicable banking, tax or regional information. Declare EU trader status even if EU distribution is excluded.',
    'Publish the supplied privacy policy and a maintained support page with real contact details. The previously checked public policy still contained the older text; publication and parity verification remain open.',
    'Resolve distribution signing and the Mac Installer Distribution identity. Export and validate the final package, then upload and select the processed build when authorized.',
    'Finish signed-app acceptance: fresh install and upgrade, folder grants and revocation, save/search/export, cross-app drops, reminders and quit behavior. Verify macOS 14 and the current shipping macOS, VoiceOver/keyboard, energy and IPv6-only networking.',
    'Compare every screenshot against the signed app, confirm rights, complete privacy/age/encryption declarations and select the release method. Apple review is still required.'
]:p(text,style='List Bullet')

page('Support page copy')
p('Replace the two contact placeholders before publishing. Add the Quick Guide PDF and the privacy policy link to the support page.','Caption')
for title,body in SUPPORT:
    ph=h(title,2);ph.paragraph_format.space_before=Pt(7);ph.paragraph_format.space_after=Pt(5)
    pp=p(body);pp.paragraph_format.space_after=Pt(5)
link('Read the DaBin privacy policy',P['privacyPolicyURL'])

page('DaBin privacy and your data')
p(f'The following is the full policy bundled with DaBin {VERSION}. Publish the matching text at the public Privacy Policy URL before submission. It covers both the direct download and Mac App Store distribution channels.', 'Caption')
for block in POLICY.read_text().split('\n\n'):
    block=block.strip()
    if not block:continue
    if block.startswith('# '):continue
    elif block.startswith('## '):
        ph=h(block[3:].replace('&','and'),2)
        ph.paragraph_format.space_before=Pt(8);ph.paragraph_format.space_after=Pt(5)
    else:
        para=p();para.paragraph_format.line_spacing=1.04;para.paragraph_format.space_after=Pt(6)
        parts=re.split(r'(\*\*.*?\*\*)',block)
        for part in parts:
            run=para.add_run(part.strip('*') if part.startswith('**') else part)
            if part.startswith('**'):run.bold=True

page('Files and reference sources')
h('Package contents',2)
p('DaBin App Store Content is the editable submission document. DaBin Quick Guide is the updated customer PDF. Screenshots contains the three original PNGs; Assets contains the current 1024-pixel app icon and bundled ICNS for reference. Copy contains individual listing fields, reviewer notes, support copy, metadata JSON and the full policy. The package manifest records file sizes and checksums.')
p('The app icon is delivered in the app build. An App Store preview video is optional and is not included in this pack. The updated PDF is a support and review attachment, not a substitute for product page screenshots.')
h('Verification scope',2)
p(f'The selected source and native screenshot fixture are version {VERSION} build {BUILD}. Screenshots use fictional records and production native views. Compare them with the final distribution-signed app. Automated source checks and local preparation evidence do not complete owner declarations or signed-app acceptance.')
p('This document concerns the Mac App Store channel. A separately installed direct-download app has its own update channel. The local direct-update evidence is separate from distribution-signed Store acceptance. This pack does not report an App Store upload, submission or approval.')
h('Apple references',2)
p(f'Apple references last checked {args.apple_audit_date}. Recheck the live App Store Connect forms before entering or submitting the prepared content.', 'Caption')
for title,url in [
('Product page fields and limits','https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/'),
('App information and content rights','https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/'),
('Mac screenshot specifications','https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/'),
('App Review Guidelines','https://developer.apple.com/app-store/review/guidelines/'),
('App Privacy details','https://developer.apple.com/app-store/app-privacy-details/'),
('Current age rating questionnaire','https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/'),
('EU trader requirements','https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/'),
('Distribution and release workflow','https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases'),
('Current submission requirements','https://developer.apple.com/news/upcoming-requirements/')]:link(title,url)
h('Local sources',2)
p(f'Product fields: {args.metadata_file.relative_to(ROOT) if args.metadata_file.is_absolute() else args.metadata_file}. Privacy: the selected release’s bundled PrivacyPolicy.md. Native images: {SCREENSHOTS.relative_to(ROOT)}/manifest.json. Release evidence: {args.qa_report or chr(91)+"CURRENT QA REPORT PENDING"+chr(93)}. The package contains separate copies of the public fields for App Store Connect.')

verify_unchanged(release)
doc.save(OUT/'DaBin-App-Store-Content.docx')
(OUT / 'authoring-inputs.json').write_text(json.dumps({'version': VERSION, 'build': BUILD, 'preparedDate': PREPARED_DATE, 'metadataSHA256': hashlib.sha256(args.metadata_file.read_bytes()).hexdigest(), 'screenshotManifestSHA256': hashlib.sha256((SCREENSHOTS / 'manifest.json').read_bytes()).hexdigest(), 'nativeRoot': str(NATIVE.relative_to(ROOT)), 'moduleReceipt': str(release['moduleStamp'].relative_to(NATIVE)) if release['moduleStamp'].is_relative_to(NATIVE) else str(release['moduleStamp']), 'moduleReceiptSHA256': hashlib.sha256(release['moduleStamp'].read_bytes()).hexdigest(), 'policySHA256': hashlib.sha256(POLICY.read_bytes()).hexdigest(), 'qaReport': args.qa_report, 'qaReportSHA256': hashlib.sha256(qa_evidence.read_bytes()).hexdigest() if qa_evidence and qa_evidence.is_file() else None, 'qaStatus': args.qa_status, 'qaSummary': args.qa_summary, 'performanceStatus': args.performance_status, 'performanceSummary': args.performance_summary, 'knownIssues': args.known_issue, 'pendingReleaseGates': META.get('pendingGates', []), 'submissionReady': False, 'visualReview': 'Pending rendering and inspection of every DOCX page.'}, indent=2) + '\n')
print(OUT/'DaBin-App-Store-Content.docx')
