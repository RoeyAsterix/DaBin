#!/usr/bin/env python3
"""Render DaBin campaign assets from native fixture UI and the exact production robot.
Run with Python 3 + Pillow on macOS. No network or personal app data is accessed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import json, shutil, hashlib

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1]
OUT = KIT / '03_Graphics'
OUT.mkdir(exist_ok=True)
BG = '#F7F3EB'; INK = '#24302E'; ACCENT = '#D87552'; MUTED = '#64706A'
FONT = '/System/Library/Fonts/SFNS.ttf'

def font(size, weight='Regular'):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f

def text(im, s, xy, size=36, fill=INK, weight='Regular', anchor='lt', spacing=10):
    d = ImageDraw.Draw(im)
    for i, line in enumerate(s.split('\n')):
        d.text((xy[0], xy[1] + i * (size + spacing)), line, font=font(size, weight), fill=fill, anchor=anchor)

def paste(im, src, xy, size=None):
    obj = src.copy().convert('RGBA') if isinstance(src, Image.Image) else Image.open(HERE/src).convert('RGBA')
    if size: obj.thumbnail(size, Image.Resampling.LANCZOS)
    im.alpha_composite(obj, (int(xy[0]),int(xy[1])))
    return obj.size

def canvas(size): return Image.new('RGBA', size, BG)

def save(im, name, transparent=False, folder=OUT):
    p=folder/name
    (im if transparent else im.convert('RGB')).save(p)
    return p

def pill(im, label, xy, size=25):
    d=ImageDraw.Draw(im);f=font(size,'Semibold'); b=d.textbbox((0,0),label,font=f)
    w=b[2]-b[0]+42;h=size+32
    d.rounded_rectangle((xy[0],xy[1],xy[0]+w,xy[1]+h),radius=h//2,fill='#EBE4D6')
    text(im,label,(xy[0]+21,xy[1]+14),size,weight='Semibold')

def brand(im, xy=(54,44), size=31):
    x,y=xy;d=ImageDraw.Draw(im)
    d.rounded_rectangle((x,y,x+7,y+size),radius=3,fill=ACCENT)
    text(im,'DaBin',(x+21,y-2),size,weight='Bold')

def footer(im, y, x=54, large=False):
    text(im,'Free. No account. Saved on your Mac.',(x,y),26 if large else 20,weight='Medium')
    text(im,'Apple Silicon · macOS 14 or later',(x,y+(46 if large else 36)),20 if large else 15,fill=MUTED)

def native_crop(name):
    p=HERE/f'DABIN__NATIVE_RENDER__{name}.png'
    im=Image.open(p).convert('RGBA').crop((260,328,2620,1732))
    # Keep every interior native pixel unchanged; remove only the known exterior
    # canvas background, connected from the border (corners around frame).
    bg=im.getpixel((0,0))[:3]
    mask=Image.new('L',im.size,255);data=[]
    for pix in im.get_flattened_data():data.append(0 if max(abs(pix[i]-bg[i]) for i in range(3))<=1 else 255)
    mask.putdata(data)
    # All matched exterior pixels are known source backdrop; interiors never use this color.
    im.putalpha(mask)
    im.save(HERE/f'DABIN__UI__{name}.png')

for mode in ['IDLE','HUNGRY','DELIGHTED']:
    p=HERE/f'DABIN__ROBOT_CANVAS__{mode}.png'
    if p.exists():
        im=Image.open(p).convert('RGBA');im.crop(im.getchannel('A').getbbox()).save(HERE/f'DABIN__ROBOT__{mode}.png')
for n in ['INBOX','PROJECTS','FOCUS','SEARCH','STUDIO_PROJECT']:native_crop(n)

# Three editorial tokens; these illustrate input kinds, never masquerade as app controls.
for kind in ['NOTE','LINK','SCREENSHOT']:
    im=Image.new('RGBA',(680,440),(0,0,0,0));d=ImageDraw.Draw(im)
    d.rounded_rectangle((22,22,658,418),radius=34,fill='white',outline='#D4D0C9',width=3)
    d.rounded_rectangle((50,49,169 if kind!='SCREENSHOT' else 270,104),radius=17,fill='#F4E6D8')
    text(im,kind.title(),(68,64),28,weight='Semibold')
    if kind=='NOTE':
        text(im,'Warm clay.\nDeep teal.\nSoft cream.',(53,151),47,weight='Medium',spacing=18)
    elif kind=='LINK':
        text(im,'example.com/studio',(52,183),40,weight='Medium')
        d.line((55,263,565,263),fill=ACCENT,width=5)
        text(im,'A link worth keeping.',(53,307),27,fill=MUTED)
    else:
        sample=Image.open(HERE/'DABIN__SAMPLE__STUDIO_REFERENCE.png').convert('RGBA');sample.thumbnail((570,287),Image.Resampling.LANCZOS);paste(im,sample,(54,115))
    save(im,f'DABIN__TOKEN__{kind}.png',transparent=True,folder=HERE)

# Signature landscape launch creative.
im=canvas((1200,630));brand(im)
text(im,'FREE APP FOR YOUR MAC',(55,113),18,fill=MUTED,weight='Semibold')
text(im,'Feed DaBin.',(53,160),70,weight='Bold')
text(im,'Save now.\nFind it later.',(55,259),47,weight='Medium',spacing=11)
d=ImageDraw.Draw(im);d.ellipse((735,139,1139,543),fill='#EEDDCF')
paste(im,'DABIN__ROBOT__IDLE.png',(724,212),(420,340))
paste(im,'DABIN__TOKEN__NOTE.png',(652,131),(159,103))
paste(im,'DABIN__TOKEN__LINK.png',(991,114),(170,111))
paste(im,'DABIN__TOKEN__SCREENSHOT.png',(939,449),(210,136))
footer(im,524)
save(im,'DABIN__SOCIAL__LANDSCAPE_1200x630.png')

# Square feed post.
im=canvas((1080,1080));brand(im,(60,49),34)
pill(im,'Free for Mac',(780,43),22)
text(im,'Feed DaBin.',(60,140),97,weight='Bold')
text(im,'Save now. Find it later.',(64,263),44,weight='Medium')
d=ImageDraw.Draw(im);d.ellipse((275,400,795,920),fill='#EEDDCF')
paste(im,'DABIN__ROBOT__IDLE.png',(222,423),(600,484))
paste(im,'DABIN__TOKEN__NOTE.png',(71,373),(235,152))
paste(im,'DABIN__TOKEN__LINK.png',(766,419),(244,158))
paste(im,'DABIN__TOKEN__SCREENSHOT.png',(737,727),(257,167))
footer(im,956,x=60,large=True)
save(im,'DABIN__SOCIAL__SQUARE_1080x1080.png')

# Portrait story/reel cover (keep headline and robot away from common UI edges).
im=canvas((1080,1920));brand(im,(76,143),46)
text(im,'Feed DaBin.',(73,295),111,weight='Bold')
text(im,'Save now.\nFind it later.',(80,465),80,weight='Medium',spacing=24)
d=ImageDraw.Draw(im);d.ellipse((220,855,930,1565),fill='#EEDDCF')
paste(im,'DABIN__ROBOT__IDLE.png',(116,953),(835,674))
paste(im,'DABIN__TOKEN__NOTE.png',(61,790),(325,211))
paste(im,'DABIN__TOKEN__LINK.png',(689,824),(330,214))
paste(im,'DABIN__TOKEN__SCREENSHOT.png',(695,1330),(304,197))
footer(im,1660,x=80,large=True)
save(im,'DABIN__SOCIAL__VERTICAL_1080x1920.png')

# Outcome-led actual product cards for websites, press and landscape social.
cards=[('INBOX','Catch the useful bits.','Save notes, images and files in your Inbox.'),
       ('SEARCH','Find that screenshot.','Search words inside supported images saved to DaBin.'),
       ('STUDIO_PROJECT','Keep a project together.','Your image, link and note in one place.')]
for i,(n,headline,caption) in enumerate(cards,1):
    im=canvas((1920,1080));brand(im,(78,47),29)
    text(im,headline,(76,113),73,weight='Bold')
    text(im,caption,(80,201),31,fill=MUTED)
    paste(im,f'DABIN__UI__{n}.png',(289,274),(1342,799))
    text(im,f'{i:02d}',(79,299),22,fill=ACCENT,weight='Bold')
    text(im,'Actual DaBin UI\nFictional sample content',(79,922),20,fill=MUTED,spacing=7)
    save(im,f'DABIN__OUTCOME__{i:02d}_{n}_1920x1080.png')

# Pristine identity assets (same as native source, no recoloring or redesign).
shutil.copyfile(HERE/'DABIN__ROBOT__IDLE.png',OUT/'DABIN__ROBOT__TRANSPARENT.png')
shutil.copyfile(HERE/'DABIN__APP_ICON__1024.png',OUT/'DABIN__APP_ICON__1024.png')
# Empty video background and exact editorial content tokens.
save(canvas((1920,1080)),'DABIN__VIDEO__BACKGROUND_1920x1080.png',folder=HERE)

# Asset gallery/contact sheet for visual QA.
files=sorted(OUT.glob('DABIN__*.png'))
cols=3;cw,ch=440,370;sheet=Image.new('RGB',(cols*cw,((len(files)+cols-1)//cols)*ch),'#E5E0D6')
for k,p in enumerate(files):
    src=Image.open(p).convert('RGBA');src.thumbnail((cw-26,ch-71),Image.Resampling.LANCZOS)
    x=(k%cols)*cw+(cw-src.width)//2;y=(k//cols)*ch+13
    base=Image.new('RGBA',sheet.size,(0,0,0,0));base.alpha_composite(src,(x,y));sheet.paste(base,mask=base.getchannel('A'))
    ImageDraw.Draw(sheet).text(((k%cols)*cw+13,(k//cols)*ch+ch-47),p.name,font=font(15,'Regular'),fill=INK)
sheet.save(HERE/'DABIN__QA__GRAPHICS_CONTACT_SHEET.png')
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>DaBin graphics</title><style>body{background:#f7f3eb;color:#24302e;font:18px -apple-system,sans-serif;margin:40px}h1{font-size:42px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}figure{margin:0;background:#ece5da;padding:16px;border-radius:16px}img{width:100%;max-height:600px;object-fit:contain}figcaption{font-size:14px;margin-top:10px;overflow-wrap:anywhere}</style><h1>Feed DaBin</h1><p>Launch graphics · actual native UI · fictional sample content.</p><main>'''
for p in files:html+=f'<figure><a href="{p.name}"><img src="{p.name}" alt="{p.stem.replace("__"," ")}"></a><figcaption>{p.name}</figcaption></figure>'
html+='</main></html>'
(OUT/'Graphics-Gallery.html').write_text(html)
(OUT/'Usage.txt').write_text('DaBin launch graphics\n\nUse the landscape 1200×630 post for X, LinkedIn and launch announcements. Use the square 1080×1080 for Instagram or community posts, and the portrait 1080×1920 as a Reel/Story cover. Outcome cards show actual native app controls with fictional records. UI can scroll; only visible content is represented.\n\nThe transparent robot is the current production Quiet Orbit character. The App Icon is the existing official DaBin app icon and is preserved separately; its design differs from the current desktop robot. Do not treat it as a replacement character.\n\nAssets are launch-ready creative drafts. Publish after the App Store listing is live and insert its real link into accompanying copy. No App Store badge or fabricated listing URL is included. Compatibility: Apple Silicon, macOS 14 or later. Search covers content saved in DaBin and local text recognition works with supported images/documents.\n')
print('Rendered',len(files),'public graphics with contact sheet.')
