from pathlib import Path
import json, html
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.lib.utils import ImageReader
from pypdf import PdfReader
ROOT=Path('/Users/roeylibfeld/Documents/KARI Creatives/DaBin/marketing/launch-kit-2026-10-04')
DEST=ROOT/'01_Launch_Playbook/DaBin_Launch_Guide.pdf'
PACK=Path('/Users/roeylibfeld/Documents/KARI Creatives/DaBin/docs/app-store/submission-pack-0.4.31-86')
W,H=595.28,841.89
NAVY=colors.HexColor('#17212d'); TEAL=colors.HexColor('#187f85'); MUTED=colors.HexColor('#59636b'); CREAM=colors.HexColor('#f3f0e9'); LINE=colors.HexColor('#d6d9d4'); PALE=colors.HexColor('#e6eeee'); WHITE=colors.white
styles={
'body':ParagraphStyle('body',fontName='Helvetica',fontSize=10.6,leading=15.7,textColor=NAVY,spaceAfter=0),
'small':ParagraphStyle('small',fontName='Helvetica',fontSize=9,leading=13.2,textColor=MUTED),
'card':ParagraphStyle('card',fontName='Helvetica',fontSize=10,leading=14.6,textColor=NAVY),
'heading':ParagraphStyle('heading',fontName='Helvetica-Bold',fontSize=16,leading=20,textColor=NAVY),
'white':ParagraphStyle('white',fontName='Helvetica',fontSize=11,leading=16.2,textColor=WHITE),
'bigwhite':ParagraphStyle('bigwhite',fontName='Helvetica-Bold',fontSize=21,leading=27,textColor=WHITE),
'url':ParagraphStyle('url',fontName='Helvetica',fontSize=8.5,leading=12,textColor=TEAL,wordWrap='CJK'),
}
c=canvas.Canvas(str(DEST),pagesize=(W,H)); c.setTitle('DaBin - Launch Guide'); c.setAuthor('DaBin marketing package'); c.setSubject('A practical launch plan for DaBin for Mac');
pageNo=0; bounds=[]
def para(text,x,y,width,sty='body',space=10):
    p=Paragraph(text,styles[sty]); pw,ph=p.wrap(width,1000)
    if y-ph<66: raise ValueError(f'Overflow page {pageNo}: {y-ph} {text[:70]}')
    p.drawOn(c,x,y-ph); bounds.append({'page':pageNo,'bottom':round(y-ph,2),'height':round(ph,2),'text':text[:80]})
    return y-ph-space

def base(section,title,subtitle=None):
    global pageNo
    pageNo+=1
    c.setFillColor(CREAM); c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(TEAL); c.rect(42,H-48,W-84,5,fill=1,stroke=0)
    c.setFillColor(TEAL); c.setFont('Helvetica-Bold',9); c.drawString(42,H-76,'DABIN / '+section.upper())
    c.setFillColor(NAVY); c.setFont('Helvetica-Bold',30); c.drawString(42,H-118,title)
    y=H-139
    if subtitle: y=para(subtitle,42,y,W-84,'small',24)
    c.setStrokeColor(LINE); c.line(42,48,W-42,48)
    c.setFont('Helvetica',8); c.setFillColor(MUTED); c.drawString(42,33,'Prepared 4 October 2026 / Local launch drafts')
    c.drawRightString(W-42,33,f'{pageNo:02d} / 09')
    return y

def heading(title,y): return para(title,42,y,W-84,'heading',9)
def text(txt,y,sty='body'): return para(txt,42,y,W-84,sty,13)
def bullet(txt,y): return para('<b>•</b>  '+txt,45,y,W-90,'body',8)
def rule(y): c.setStrokeColor(LINE);c.line(42,y,W-42,y); return y-18

def box(title,content,x,y,width,height,bg=WHITE):
    c.setFillColor(bg); c.roundRect(x,y-height,width,height,12,fill=1,stroke=0)
    iy=y-17
    iy=para('<b>'+title+'</b>',x+17,iy,width-34,'body',8)
    iy=para(content,x+17,iy,width-34,'card',0)
    if iy<y-height+10: raise ValueError(f'Card overflow page {pageNo}')

def end():c.showPage()
# 1 cover, special layout.
y=base('Launch guide','Save now. Find it later.','A practical marketing package for a free local Mac app.')
c.drawImage(str(ROOT/'06_Source/assets/DABIN__ROBOT__DELIGHTED.png'),42,y-90,105,84.75,mask='auto',preserveAspectRatio=True)
y=para('A little robot for the<br/><b>useful bits of your day.</b>',156,y-5,W-198,'heading',20)-34
c.setFillColor(NAVY);c.roundRect(42,y-149,W-84,149,16,fill=1,stroke=0)
para('The robot earns attention.<br/>The workflow earns the download.',62,y-21,W-124,'bigwhite',15)
para('Lead with a short Feed DaBin film, then show how a saved screenshot, reference or note can be found again on the Mac.',62,y-89,W-124,'white',0)
y-=178
y=heading('Start with designers.',y)
y=text('Give creative freelancers one clear example: save a reference image, a useful link and an idea into a fictional project. Then find one again. Expand to students and developers after the first week of feedback.',y)
y=rule(y)
y=text('<b>This kit is prepared locally.</b> Day 1 starts only when DaBin is publicly downloadable in the intended App Store territories. Complete the real app URL, website and contact fields before publication. Outreach, posts and Apple nominations remain unsent drafts.',y,'small')
y=text('<b>Compatibility:</b> Apple Silicon Macs, macOS 14 or later.<br/><b>Product basis:</b> submission-pack 0.4.31 (86); not evidence of App Store approval.<br/><b>Inside the ZIP:</b> launch plan, editable copy, graphics, films, landing page and sources.',y,'small')
end()
# 2
y=base('Positioning','One useful promise.','A concrete outcome should be visible before you list features.')
y=text('<b>Primary message:</b> Save now. Find it later. Keep it on your Mac.',y)
box('DESIGNERS / START HERE','Collect a reference image, a link, a note and a next task in the fictional Studio Refresh project. Show the real Projects view.',42,y,511,111);y-=132
box('STUDENTS / TEST IN WEEK THREE','Keep fictional lecture screenshots and reading notes together. Find a word in supported content saved into DaBin. Avoid promises about grades or study performance.',42,y,511,111);y-=132
box('DEVELOPERS / TEST IN WEEK THREE','Save a documentation link, a named snippet and the next step with a project. Do not imply code execution, AI answers or unshipped integrations.',42,y,511,111);y-=135
y=heading('Why people should try it',y)
y=text('A visible desktop drop target makes capture approachable. A local board keeps useful saved content and project resources close. No account is required, so the first demonstration can get straight to saving and finding.',y)
y=text('<b>Privacy wording:</b> No account, ads, analytics or cloud sync. Saved captures and recognized text stay on this Mac. Optional manual-link previews can contact websites. Use specific facts, not an absolute promise that nothing ever leaves the computer.',y,'small')
end()
# 3
y=base('Creative system','Three demonstrations.','Use fictional sample content. Keep the interface readable and the benefit specific.')
y=heading('1. Feed DaBin / 22 seconds',y)
y=text('Open with the robot and a link, image and note. Connect the animation to actual app views. Finish with the save-and-find promise, a free-download action and compatibility. The Blender sequence is a social/website brand introduction.',y)
y=text('<b>Files:</b> 04_Video contains landscape, portrait and silent exports, audio and a subtitle sidecar. Watch the final film with sound and muted. Verify crops and subtitles before publication.',y,'small')
y=heading('2. Where did that screenshot go?',y)
y=text('Use a neutral filename and put the word terracotta inside a fictional saved screenshot. Record an actual DaBin search returning that word, then open the saved result. Search is local and covers supported content saved into DaBin.',y)
y=heading('3. One project, useful bits together',y)
y=text('Show the fictional Studio Refresh project with an image, link, note and task. Organization is optional: save first, sort when it helps. Student and developer examples reuse the same workflow.',y)
y=heading('Outcome-led App Store screenshots',y)
thumbW=155; thumbH=96.9
for idx,(fname,label) in enumerate([('DABIN__APP_STORE__01_INBOX.png','Catch the useful bits.'),('DABIN__APP_STORE__02_PROJECTS.png','Keep a project together.'),('DABIN__APP_STORE__03_FOCUS.png','Give one task attention.')]):
    x=42+idx*178
    c.drawImage(str(PACK/'Screenshots'/fname),x,y-thumbH,thumbW,thumbH,mask='auto')
    para(label,x,y-thumbH-9,thumbW,'small',0)
y-=thumbH+49
y=text('These are real source screenshots. Compare them with the distributed build. A saved-screenshot search image is an additional proposed capture; do not present a composed mockup as proof of actual search.',y,'small')
y=text('<b>Apple preview distinction:</b> Apple app previews use footage captured on the device. Make and validate a separate native recording if an App Store preview is wanted; the brand film is not automatically an upload-ready preview.',y,'small')
end()
# 4
y=base('Preparation','Make the launch concrete.','A complete release and working destination links matter more than a chosen calendar date.')
y=heading('Before publication',y)
for b in ['Verify the final distributed app and actual Free price in the intended territories. This kit does not establish approval or availability.','Complete the App Store URL, public website, support and contact details. Replace every bracketed field.','Compare screenshots and demonstrations against the public build. Hide personal captures, notifications and private project material.','Watch video exports with sound and muted; check subtitle accuracy, crop, text and compatibility.'] : y=bullet(b,y)
y=rule(y)
y=heading('Before each channel goes live',y)
for b in ['Read the current r/macapps rules and account eligibility. Complete its required developer/AI disclosure and respect promotion timing.','Use a personal Product Hunt maker identity, an accurate gallery and a staffed launch day. Ask for comments and questions, never upvotes.','Read a recipient\'s recent work yourself and use the official contact route. Tailor one short message; no bulk distribution.'] : y=bullet(b,y)
y=rule(y)
y=heading('Apple featuring',y)
y=text('If the launch is still ahead, Apple recommends submitting plans at least three weeks early where practical. The draft in 02_Copy maps the real product into a launch nomination. If already public, nominate only an actual future meaningful update with an accurate date.',y)
y=text('A nomination is editorial consideration. Do not publish Apple featuring or award claims unless selection is documented. Accessibility statements must match an evaluation of the exact shipping build.',y,'small')
end()
# 5
y=base('First month','A month of useful stories.','The full editable daily plan is 01_Launch_Playbook/30_Day_Calendar.html and .json.')
phases=[('DAYS 1-7 / LAUNCH','Verify public availability, publish one main clip and one rule-compliant Mac community post, answer questions and pitch the first three relevant targets.'),('DAYS 8-14 / SEARCH','Show the real saved-screenshot text-search trick. Prepare or run Product Hunt when ready. Tailor two more pitches; follow up once where welcome.'),('DAYS 15-21 / AUDIENCE TESTS','Try a student example, then a developer example. Answer an actual question with a short clip. Contact two more relevant targets.'),('DAYS 22-30 / LEARN AND REFRESH','Reach ten selected pitches only if fit warrants it. Publish the project demo, share any actual coverage, review results and choose the next audience and hook.')]
for title,body in phases:
    box(title,body,42,y,511,106);y-=116

y=heading('Keep the effort manageable',y)
y=text('Plan for 30-45 minutes on publishing days, a brief daily reply check in launch week and a 45-minute weekly review. Start with organic channels and existing accounts. Paid partnerships are optional later, with a deliberate capped budget.',y)
y=text('Calendar days can move to match readiness. This plan is not a scheduled automation. Do not repeat a subreddit promotion before the current cooldown allows it.',y,'small')
end()
# 6
y=base('Outreach','Ten routes to investigate.','Official routes checked 4 October 2026. Priority and fit are marketing judgments, not confirmed interest.')
targets=json.loads((ROOT/'01_Launch_Playbook/creator-targets.json').read_text())['targets']
rows=[[Paragraph('<b>Target / route</b>',styles['small']),Paragraph('<b>A useful angle</b>',styles['small'])]]
angles=['Native Mac capture/search workflow. Offer independent testing.','Creative references and calm project organization.','Concrete free Mac utility with saved-content search.','Personally edited pitch after reading the publisher\'s guide.','Fictional design-reference project; check current activity.','Concise Mac launch facts and real app views.','Practical Mac-app discovery; coverage is uncertain.','A short Apple productivity note, clear subject and workflow.','Optional paid/feature inquiry: fit, rates and rights first.','Optional paid partnership inquiry; no booking assumed.']
for t,a in zip(targets,angles):
    name=html.escape(t['name'])
    rows.append([Paragraph(f'<a href="{t["url"]}" color="#187f85"><b>{name}</b></a><br/>{html.escape(t["route"])}',styles['small']),Paragraph(a,styles['small'])])
t=Table(rows,colWidths=[231,280]);t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(-1,0),PALE),('ROWBACKGROUNDS',(0,1),(-1,-1),[WHITE,colors.HexColor('#faf9f5')]),('BOTTOMPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,-1),10),('LEFTPADDING',(0,0),(-1,-1),12),('RIGHTPADDING',(0,0),(-1,-1),12),('LINEBELOW',(0,0),(-1,-1),0.4,LINE)]));tw,th=t.wrap(511,900)
if y-th<100:raise ValueError(f'Table overflow p6 {th} {y}')
t.drawOn(c,42,y-th);y-=th+19
y=text('<b>Skip MacMost:</b> its official contact page explicitly rejects product-review and marketing requests. TidBITS rejects press releases; use only a personally considered pitch. Outreach drafts remain unsent, and paid routes require a budget choice.',y,'small')
end()
# 7
y=base('Ready copy','A few words that work.','Full platform drafts, outreach, press material, store fields and replies are in 02_Copy.')
box('SHORT LAUNCH POST','Meet DaBin: a little robot for the useful bits of your day.<br/>Save notes, links, images, files and tasks on your Mac - then find them again.<br/><b>Free. No account. Apple Silicon, macOS 14+.</b><br/>Add the real App Store link.',42,y,511,150);y-=173
box('SCREENSHOT SEARCH POST','Where did that screenshot go?<br/>Save it into DaBin, then find a word inside it with local text search.<br/><b>Free for Apple Silicon Macs, macOS 14+.</b><br/>Attach the real saved-screenshot search demonstration.',42,y,511,134);y-=156
box('CREATOR PITCH CORE','DaBin is a free local Mac app with a robot drop target. The short demo saves fictional project references, then shows how to find a word inside a saved screenshot. Give the public app and demo links, add a truthful reason for the recipient\'s fit, and invite an independent opinion.',42,y,511,128);y-=151
y=heading('Match the destination',y)
y=text('Reddit needs the required structured developer format and honest AI disclosure. Product Hunt needs a clear tagline, actual gallery and a maker comment. The press release is conditional on publication. App Store listing copy avoids price promises and competitor keywords.',y)
y=text('No founder origin story, download count, testimonial or endorsement is invented. The question "Why is it free?" needs the owner\'s real answer.',y,'small')
end()
# 8
y=base('Measurement','Learn without app telemetry.','Use Apple campaign reports when available, platform reach and voluntary workflow feedback.')
y=heading('Record one row per channel and asset',y)
y=text('Log the publication time, campaign token, actual Apple-generated URL, audience, asset, minutes spent and comparable reporting dates. Record views, product-page views, first-time downloads and outreach replies only when available.',y)
box('BEFORE CAMPAIGN LINKS APPEAR','Use the real untagged App Store URL. Log the post and time, and mark source attribution unavailable. A same-day download spike is an association, not proof that a particular post caused it.',42,y,511,115);y-=139
box('WHEN APPLE DATA IS AVAILABLE','Generate campaign links in App Store Connect rather than guessing app IDs or provider tokens. New apps may need live download data first. Small metrics can be withheld under reporting thresholds; blank or unavailable is not zero.',42,y,511,126);y-=148
y=heading('The 45-minute weekly review',y)
for b in ['Compare the same date range and metric definitions across channels.','Read voluntary feedback: what did people save, and could they find it again? Ask for a description, not their private content.','Choose one useful demo to repeat and one unclear claim to improve.','No in-app analytics means product activation and continued use are not measured by this plan. Do not report inferred retention as a fact.']: y=bullet(b,y)
y=text('Apple\'s campaign guide describes first-time download attribution within 24 hours and last-link credit when multiple campaign links are used. Recheck the current definitions. Native platform views/clicks and Apple metrics can have different scopes.',y,'small')
end()
# 9
y=base('Use and sources','Ready when the release is.','Begin with the checklist, then one film, one community and a few relevant conversations.')
y=heading('Use the package in this order',y)
for b in ['01_Launch_Playbook: complete the launch checklist, follow the calendar and keep the tracker honest.','02_Copy: fill every owner/live-link field; adapt to current channel requirements. All messages are unsent drafts.','03_Graphics + 04_Video: use the right aspect ratio, actual app views and truthful media labels.','05_Landing_Page: review the local page and replace its destinations before hosting.','06_Source + 07_QA: retain source/provenance and verify current exports before reuse.']:y=bullet(b,y)
y=heading('The claim gate',y)
y=text('Free price must match the live listing. Search covers supported saved DaBin content, not the whole Mac. Optional manual-link previews can contact websites. DaBin does not separately encrypt its archive. Do not invent Apple featuring, accessibility evaluation, permanent pricing, founder story or measured time savings.',y)
y=rule(y)
y=heading('Primary references',y)
refs=[('Apple: product-page guidance','https://developer.apple.com/app-store/product-page/'),('Apple: featuring nominations','https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/'),('Apple: campaign links','https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links'),('Product Hunt: official launch guide','https://www.producthunt.com/launch'),('r/macapps: developer-post notice','https://www.reddit.com/r/macapps/comments/1r6d06r/new_post_requirements_to_combat_low_quality/')]
for title,url in refs:
    y=para(f'<a href="{url}" color="#187f85"><b>{html.escape(title)}</b></a>',42,y,511,'small',3)
    y=para(html.escape(url),42,y,511,'url',9)
y=text('The complete product authority and official contact/policy links are in Sources_and_Provenance.txt. This guide uses the current local submission pack 0.4.31 (86) and user-stated Free intent. Web sources were checked on 4 October 2026; recheck during launch.',y,'small')
end()
c.save()
reader=PdfReader(str(DEST));assert len(reader.pages)==9
texts=[p.extract_text() for p in reader.pages]
assert all(len(t)>250 for t in texts)
(ROOT/'01_Launch_Playbook/PDF_QA.txt').write_text('DABIN LAUNCH GUIDE / PDF QA\nPrepared 4 October 2026.\nPDF: DaBin_Launch_Guide.pdf\nPages: 9\nText extraction: all pages contain expected readable text.\nAuthoring layout checks: all body elements fit above the footer margin.\nVisual rendering: pending.\nNo fillable fields.\n')
Path('/tmp/dabin-launch-copy-build/pdf_layout.json').write_text(json.dumps(bounds,indent=2))
print(DEST)
print('Pages:',len(reader.pages),'Text chars:',[len(t) for t in texts])
print('Lowest body bottom:',min(b['bottom'] for b in bounds))
