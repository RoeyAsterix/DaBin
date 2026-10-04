#!/usr/bin/env python3
"""Build a local, reviewable submission document from verified release copy."""
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

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/app-store/submission-pack-0.4.31-86'
OUT.mkdir(parents=True, exist_ok=True)
COPY = OUT / 'Copy'
COPY.mkdir(exist_ok=True)
SHOTS = OUT / 'Screenshots'
SHOTS.mkdir(exist_ok=True)
ASSETS = OUT / 'Assets'
ASSETS.mkdir(exist_ok=True)
NATIVE = ROOT / 'native/build/store-preparation-20261004/native'
shutil.copy2(NATIVE / 'Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png', ASSETS / 'DaBin-App-Icon-1024.png')
shutil.copy2(NATIVE / 'Resources/AppIcon.icns', ASSETS / 'AppIcon.icns')
META = json.loads((ROOT / 'docs/app-store/metadata-en-US.json').read_text())
assert META['candidate']['version'] == '0.4.31' and META['candidate']['build'] == '86'
P = META['productPage']
MANIFEST = json.loads((ROOT / 'docs/app-store/screenshots/0.4.31-86/manifest.json').read_text())
for shot in MANIFEST['screenshots']:
    source = ROOT / 'docs/app-store/screenshots/0.4.31-86' / shot['file']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == shot['sha256']
    im = Image.open(source)
    assert im.size == (1440, 900) and im.mode == 'RGB'
    shutil.copy2(source, SHOTS / source.name)

WHATS_NEW = ('Auto Capture is easier to recognize at a glance. A red recording symbol in the menu bar shows when monitoring is active, with distinct Ready, Paused and Off states. We have also clarified the privacy policy and the controls for your saved data.')
SUPPORT = [
    ('Contact support', 'Email: [PUBLIC SUPPORT EMAIL]\nSupport page: [PUBLIC SUPPORT URL]\nInclude your DaBin version, macOS version and the steps that led to the issue. Use fictional examples and remove private material from any screenshots. Do not send your capture archive, passwords or sensitive clipboard contents.'),
    ('Getting started', 'Open DaBin from its menu-bar item or double-click the desktop robot. Paste text or a link into Inbox, or drop in a file. Use the upper + button to create a task directly. Keep related work in a project and use Search to find it again.'),
    ('What does Search cover', 'Search finds content saved into DaBin, across projects and dates. You can type, use the context-menu Paste action or press Command-V in the search field. Results appear in date columns. Local text recognition also indexes supported saved images and documents; it does not search every file on your Mac.'),
    ('Does Auto Capture record my screen', 'No. Auto Capture is optional and starts off. After you enable it, DaBin can save later clipboard changes and new images added to the screenshot folder you choose. Existing clipboard contents and existing images are not imported when monitoring starts. The red menu-bar symbol indicates active monitoring. Pause or switch it off whenever you need to.'),
    ('Where is my content stored', 'On this Mac. DaBin has no account, cloud sync, advertising or analytics. Optional website previews are off by default and can contact websites for manually saved links. Automatic captures never fetch link previews. Exports and backups are stored in the location you choose; a cloud-synced destination may upload them through that service.'),
    ('How do I move content to another app', 'Drag a card or caption to a destination that accepts its text, link, image or file representation. The receiving app controls what it can accept. You can also copy and paste or export. DaBin keeps its saved content, and original source files remain in place.'),
    ('How do I back up or remove content', 'Use More > Back up archive to create a local backup. Recently Deleted lets you restore removed captures or delete them permanently. Turning Auto Capture off stops new monitoring but keeps earlier captures. See Settings > Privacy policy & data controls for complete deletion instructions.'),
    ('Which Macs are supported', 'DaBin 0.4.31 requires an Apple Silicon Mac with macOS 14 or later. The Mac App Store version receives updates through the App Store.'),
]

PUBLIC_FIELDS = {'Name':P['name'], 'Subtitle':P['subtitle'], 'Promotional text':P['promotionalText'],
                 'Description':P['description'], 'Keywords':P['keywords'],
                 'Whats New for a subsequent App Store version only':WHATS_NEW}
for label, content in PUBLIC_FIELDS.items():
    filename = re.sub(r'[^a-z0-9]+', '-', label.lower()).strip('-') + '.txt'
    (COPY / filename).write_text(content + '\n')
(COPY / 'review-notes.txt').write_text(META['review']['notes'] + '\n')
(COPY / 'support-page.txt').write_text('DaBin support\n\n' + '\n\n'.join(h+'\n'+b for h,b in SUPPORT) + '\n\nPrivacy policy\n'+P['privacyPolicyURL']+'\n')
(COPY / 'metadata-en-US.json').write_text(json.dumps(META, indent=2, ensure_ascii=False) + '\n')
POLICY = ROOT / 'native/build/store-preparation-20261004/native/Resources/PrivacyPolicy.md'
assert POLICY.read_bytes() == (ROOT / 'native/Resources/PrivacyPolicy.md').read_bytes()
shutil.copy2(POLICY, COPY / 'PrivacyPolicy.md')

doc = Document()
doc.core_properties.title = 'DaBin App Store Content'
doc.core_properties.subject = 'Mac App Store submission content for DaBin 0.4.31 build 86'
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
footer.add_run('DaBin 0.4.31  |  ')
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
p('Version 0 4 31   Build 86   English US   4 October 2026','Subtitle')
p('Use this document to populate DaBin’s Mac App Store listing, prepare the review submission and publish the supporting privacy and support content. The screenshot pages show the current native interface; the accompanying folder contains the original upload images and plain text fields.')
p('Complete the owner fields and release checks before submission. Copy only the text under the relevant field into App Store Connect. Reviewer notes are private; listing copy, support details and the privacy policy are public.')
h('App information')
table(['Field','Value','Status'],[
('Platform','macOS','Prepared'),('App name','DaBin','Name availability to confirm'),('Subtitle',P['subtitle'],'24 of 30 characters'),
('Primary category','Productivity','Proposed'),('Primary language','English US','Proposed'),('Bundle ID','com.dabin.mac','Confirm Connect record'),
('Version and build','0.4.31  /  86','Confirm build availability'),('Requirements','Apple Silicon  /  macOS 14 or later','Current build'),
('SKU','[OWNER APP SKU]','Private app record field'),('Secondary category','None proposed','Optional')], [1.55,3.15,2.13])
h('Promotional text',2);p(P['promotionalText']);p('152 of 170 characters. Public product page field.','Caption')
h('Keywords',2);p(P['keywords']);p('86 of 100 bytes. Paste as one comma-separated line.','Caption')

page('Product description')
p('Public Description field  |  1716 of 4000 characters','Caption')
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
('Screenshot 1 Inbox','DABIN__APP_STORE__01_INBOX.png','Keep the useful bits.','Save notes, images and files. Sort them when you’re ready.'),
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
('Privacy URL','Use the linked policy below after publishing the 4 October text and verifying that the public and bundled versions match.'),
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
p('The following is the full policy bundled with DaBin 0.4.31. Publish the matching text at the public Privacy Policy URL before submission. It covers both the direct download and Mac App Store distribution channels.','Caption')
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
p('The current source and native screenshot fixture are version 0.4.31 build 86. Screenshots use fictional data and show production native views. They do not show a final distribution-signed install. Automated Store testing and an isolated sandbox smoke test support preparation; the owner decisions and final signed-app checks remain separate release gates.')
p('The local installed app is the direct-download channel at 0.4.31 build 86. The submission concerns the Mac App Store channel. This document does not report an App Store upload, submission or approval.')
h('Apple references',2)
p('Checked 4 October 2026. Recheck the live App Store Connect forms before entering or submitting the prepared content.','Caption')
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
p('Product fields: docs/app-store/metadata-en-US.json. Privacy: the verified release’s bundled PrivacyPolicy.md. Native images: docs/app-store/screenshots/0.4.31-86/manifest.json. Release evidence: docs/qa/app-store-preparation-2026-10-04 and docs/qa/local-update-0.4.31-2026-10-04. The package contains copies of the public text so fields can be pasted without extracting them from Word.')

doc.save(OUT/'DaBin-App-Store-Content.docx')
print(OUT/'DaBin-App-Store-Content.docx')
