from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from pypdf import PdfReader
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/pdf/DaBin-Quick-Guide.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
NORMAL = 'Helvetica'
BOLD = 'Helvetica-Bold'

W, H = A4
INK = colors.HexColor('#362E44')
PURPLE = colors.HexColor('#6D5387')
BODY = colors.HexColor('#5F5867')
PALE = colors.HexColor('#F2EDF7')
PAPER = colors.HexColor('#FDFCFD')
LINE = colors.HexColor('#E4DDEB')
WHITE = colors.white
c = canvas.Canvas(str(OUT), pagesize=A4, pageCompression=1)
c.setTitle('DaBin | A little home for your day')
c.setAuthor('DaBin')
c.setSubject('A friendly one-page introduction and quick-start guide to DaBin for macOS')
c.setCreator('DaBin PDF guide')
blocks = []

def rect(x, top, w, h, fill, r=0, stroke=None):
    c.setFillColor(fill)
    c.setStrokeColor(stroke or fill)
    c.setLineWidth(.7)
    c.roundRect(x, H-top-h, w, h, r, fill=1, stroke=int(stroke is not None))

def line(x1, y1, x2, y2, color=LINE, width=.7):
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.line(x1,H-y1,x2,H-y2)

def text(value,x,top,size=11,font=NORMAL,color=INK):
    c.setFont(font,size)
    c.setFillColor(color)
    c.drawString(x,H-top-size*.82,value)

def right(value,x,top,size=9,font=NORMAL,color=BODY):
    c.setFont(font,size)
    c.setFillColor(color)
    c.drawRightString(x,H-top-size*.82,value)

def para(value,x,top,w,size=11,leading=15,color=BODY,max_height=None):
    p=Paragraph(value, ParagraphStyle('p',fontName=NORMAL,fontSize=size,leading=leading,textColor=color,spaceAfter=0))
    _,h=p.wrap(w,H)
    if max_height is not None:
        assert h<=max_height, (value,h,max_height)
    p.drawOn(c,x,H-top-h)
    blocks.append({'text': value, 'x':x,'top':top,'width':w,'height':h})
    return h

def image(path,x,top,w,h):
    c.drawImage(ImageReader(str(path)),x,H-top-h,width=w,height=h,mask='auto')

def icon(kind,x,top,size=20,color=PURPLE):
    c.saveState()
    c.translate(x,H-top-size)
    c.scale(size/24,size/24)
    c.setStrokeColor(color)
    c.setFillColor(color)
    c.setLineWidth(1.6)
    c.setLineCap(1)
    c.setLineJoin(1)
    if kind=='link':
        c.saveState()
        c.translate(12,12)
        c.rotate(-42)
        c.roundRect(-8,-4,11,8,4,stroke=1,fill=0)
        c.roundRect(-3,-4,11,8,4,stroke=1,fill=0)
        c.restoreState()
    elif kind=='file':
        p=c.beginPath(); p.moveTo(5,2);p.lineTo(19,2);p.lineTo(19,16);p.lineTo(13,22);p.lineTo(5,22);p.close()
        c.drawPath(p,stroke=1,fill=0)
        c.line(13,22,13,16); c.line(13,16,19,16)
        c.line(8,11,16,11);c.line(8,7,14,7)
    elif kind=='media':
        c.roundRect(2,3,20,18,3,stroke=1,fill=0)
        c.circle(8,15,1.6,stroke=1,fill=0)
        p=c.beginPath();p.moveTo(3,6);p.lineTo(9,11);p.lineTo(13,7);p.lineTo(17,12);p.lineTo(21,8)
        c.drawPath(p,stroke=1,fill=0)
    elif kind=='search':
        c.circle(10,14,6.5,stroke=1,fill=0);c.line(15,9,21,3)
    elif kind=='export':
        c.roundRect(4,3,16,12,2.5,stroke=1,fill=0)
        c.line(12,8,12,22)
        c.line(12,22,8,18)
        c.line(12,22,16,18)
    elif kind=='comment':
        p=c.beginPath();p.moveTo(3,20);p.lineTo(21,20);p.lineTo(21,7);p.lineTo(10,7);p.lineTo(5,2);p.lineTo(5,7);p.lineTo(3,7);p.close()
        c.drawPath(p,stroke=1,fill=0)
        c.line(7,15,17,15);c.line(7,11,14,11)
    elif kind=='capture':
        c.roundRect(3,4,18,15,3,stroke=1,fill=0)
        c.circle(12,11.5,4.2,stroke=1,fill=0)
        c.line(7,19,9,22);c.line(9,22,15,22);c.line(15,22,17,19)
    elif kind=='pause':
        c.roundRect(3,3,18,18,5,stroke=1,fill=0)
        c.roundRect(8,7,2.5,10,1.2,stroke=0,fill=1)
        c.roundRect(13.5,7,2.5,10,1.2,stroke=0,fill=1)
    elif kind=='move':
        c.line(12,3,12,21);c.line(3,12,21,12)
        p=c.beginPath();p.moveTo(12,21);p.lineTo(8.5,17.5);p.moveTo(12,21);p.lineTo(15.5,17.5)
        p.moveTo(12,3);p.lineTo(8.5,6.5);p.moveTo(12,3);p.lineTo(15.5,6.5)
        p.moveTo(3,12);p.lineTo(6.5,8.5);p.moveTo(3,12);p.lineTo(6.5,15.5)
        p.moveTo(21,12);p.lineTo(17.5,8.5);p.moveTo(21,12);p.lineTo(17.5,15.5)
        c.drawPath(p,stroke=1,fill=0)
    c.restoreState()

# Brand header.
rect(0,0,W,H,PAPER)
image(ROOT/'design/onepager/assets/DaBin-logo.png',40,33,126,126*256/781)
right('YOUR DAILY COMPANION',W-42,41,8.5,BOLD,PURPLE)
right('A QUICK GUIDE FOR macOS',W-42,57,8.2,color=BODY)

# A spacious introduction with the existing mascot.
text('A little home',42,113,34,BOLD)
text('for your day.',42,153,34,BOLD)
para('Keep the links, files, images and ideas you want to come back to. DaBin saves what you drop or paste into a personal daily board, right on your Mac.',42,211,306,12,17,max_height=68)
c.setFillColor(PALE)
c.circle(466,H-199,76,fill=1,stroke=0)
image(ROOT/'native/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png',382,119,167,167)

# Small familiar content icons, all pointing toward the robot itself.
for kind,x,top,angle in [('file',388,105,-9),('link',501,121,9),('media',516,242,-7)]:
    c.saveState()
    c.translate(x+17,H-top-17)
    c.rotate(angle)
    c.setFillColor(WHITE);c.setStrokeColor(LINE);c.setLineWidth(.7)
    c.roundRect(-17,-17,34,34,8,fill=1,stroke=1)
    c.restoreState()
    icon(kind,x+7,top+7,20)

x=42
for label in ['Text','Links','Files & PDFs','Images & video']:
    w=pdfmetrics.stringWidth(label,NORMAL,9.3)+22
    rect(x,291,w,25,PALE,r=12.5)
    text(label,x+11,299,9.3,color=PURPLE)
    x+=w+7

line(42,338,W-42,338)
text('START WITH THREE SMALL MOVES',42,355,9,BOLD,PURPLE)

steps=[
    ('1','Meet your robot','Move your pointer to a screen corner. Or choose <b>Below camera island</b> in Settings so your robot peeks from the notch. It stays hidden while you work.'),
    ('2','Drop or paste','Drop one or several files onto the robot, or hover and press <b>Control-V</b> or <b>Command-V</b>. Files from one move stay together in one card.'),
    ('3','Open your day','<b>Double-click</b> the robot for Daily, with the newest captures first. Use <b>Daily / Weekly</b> to switch between one day and seven.'),
]
for idx,(num,title,body) in enumerate(steps):
    x=42+idx*174
    rect(x,385,24,24,PURPLE,r=12)
    text(num,x+8,391,11,BOLD,WHITE)
    text(title,x,421,13.5,BOLD)
    para(body,x,448,151,10.5,14.7,max_height=90)

line(42,548,W-42,548)
text('AUTO CAPTURE, WHEN YOU WANT IT',42,563,9,BOLD,PURPLE)
rect(W-153,556,111,24,PALE,r=12)
text('OFF BY DEFAULT',W-138,563,8.5,BOLD,PURPLE)

rect(42,592,W-84,125,PALE,r=14)
icon('capture',56,607,22)
text('Turn it on',87,610,14,BOLD)
para('Open <b>Settings &gt; Capture</b> and enable Auto Capture. Choose a dedicated screenshot folder when asked. DaBin then saves <b>future copies</b> and new images added there.',56,640,220,9.4,12.7,max_height=66)

line(298,608,298,701,color=LINE,width=.8)
icon('pause',315,607,22)
text('Stay in control',346,610,14,BOLD)
para('Everything stays on your Mac. <b>Pause</b> any time; DaBin and common password managers are excluded by default. At <b>4 actions</b> in one clock hour, click the summary to expand and use the minus button to collapse.',315,640,224,9.4,12.7,max_height=66)

icon('export',42,740,18)
text('Find & export',68,742,11.5,BOLD)
para('Filter or search any date. <b>Export Day</b> copies or saves its complete record as UTF-8 text.',42,764,151,8.9,12.2,max_height=37)

icon('comment',216,740,18)
text('Add context',242,742,11.5,BOLD)
para('Comment, set a reminder, or press <b>+</b> for a task you can mark complete.',216,764,151,8.9,12.2,max_height=37)

icon('move',390,740,18)
text('Make it yours',416,742,11.5,BOLD)
para('Drag the logo to move the board. Settings controls theme, opacity and robot home.',390,764,151,8.9,12.2,max_height=37)

line(42,811,W-42,811)
text('Manual drag and paste always stay available.',42,820,8.5,color=BODY)
right('DaBin  /  Quick start',W-42,817,8.5,color=PURPLE)
c.showPage()
c.save()

reader=PdfReader(OUT)
assert len(reader.pages)==1
extracted=reader.pages[0].extract_text()
normalized=' '.join(extracted.split())
for required in ['camera island','Control-V','Command-V','Double-click','Daily / Weekly','Settings > Capture','OFF BY DEFAULT','future copies','dedicated screenshot folder','stays on your Mac','Pause','password managers','4 actions','expand','minus button','collapse','Export Day','complete record','UTF-8 text','Manual drag and paste']:
    assert required in normalized, required
assert '\ufffd' not in extracted
assert all(b['x']>=30 and b['x']+b['width']<=W-30 and b['top']+b['height']<803 for b in blocks)
(ROOT/'tmp/pdfs').mkdir(parents=True, exist_ok=True)
(ROOT/'tmp/pdfs/layout-check.json').write_text(json.dumps({'page_count':len(reader.pages),'page_size':'A4','paragraphs':blocks,'text':extracted},indent=2))
print(OUT)
print(f'PASS: one A4 page, {len(extracted.split())} words, all text blocks within bounds')
