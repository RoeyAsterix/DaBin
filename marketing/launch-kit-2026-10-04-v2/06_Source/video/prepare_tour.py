#!/usr/bin/env python3
"""Author editorial guide textures; native UI pixels remain untouched.

Inputs: tour_edit.json, exact native UI and robot artwork, natural-speed voice.
UI views, speech guide and cursor are distinct layers in the Blender file.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

HERE=Path(__file__).resolve().parent
KIT=HERE.parents[1]; TEX=HERE/'textures'; TEX.mkdir(exist_ok=True)
ASSETS=HERE.parent/'assets'
EDIT=json.loads((HERE/'tour_edit.json').read_text())
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
INK='#193c3b'; MUTED='#577371'; TEAL='#136c69'; PAPER='#f8f5ed'
def f(n,b=False):return ImageFont.truetype(BOLD if b else FONT,n)
def save(im,name):im.save(TEX/f'DABIN__TOUR__{name}.png')
def lines(text,font,width):
    words=text.split(); out=[]; line=''
    for word in words:
        test=(line+' '+word).strip()
        if font.getlength(test)>width and line:out.append(line);line=word
        else:line=test
    if line:out.append(line)
    return out
for layout,W,H in [('LANDSCAPE',1920,1080),('PORTRAIT',1080,1920)]:
    portrait=layout=='PORTRAIT'
    bg=Image.new('RGB',(W,H),PAPER); d=ImageDraw.Draw(bg)
    d.text((40,28 if not portrait else 42),'DaBin',font=f(32 if not portrait else 45,True),fill=INK)
    d.text((158 if not portrait else 212,35 if not portrait else 54),'Your little local companion',font=f(21 if not portrait else 27),fill=MUTED)
    if not portrait:
        d.rounded_rectangle((1610,120,1890,1000),radius=30,fill='#e6eee8')
        d.text((1650,944),'FREE FOR MAC',font=f(19,True),fill=TEAL)
        d.text((40,1040),'Apple Silicon · macOS 14+    /    Fictional example content',font=f(18),fill=MUTED)
    else:
        d.rounded_rectangle((38,1350,1042,1785),radius=35,fill='#e6eee8')
        d.text((50,1820),'Free · Apple Silicon · macOS 14+',font=f(27,True),fill=TEAL)
    save(bg,'BACKDROP_'+layout)
    for chapter in EDIT['chapters']:
        ci=chapter['id']; title=chapter['title']; bubble=chapter['bubble']
        iw,ih=(1520,70) if not portrait else (990,115)
        titleim=Image.new('RGBA',(iw,ih));td=ImageDraw.Draw(titleim)
        td.text((0,8),f'{ci:02} / {len(EDIT["chapters"]):02}',font=f(19 if not portrait else 25,True),fill=TEAL)
        tf=f(27 if not portrait else 39,True)
        tx=100 if not portrait else 130
        for k,line in enumerate(lines(title,tf,iw-tx-12)):
            td.text((tx,5+k*(tf.size+10)),line,font=tf,fill=INK)
        save(titleim,f'TITLE_{layout}_{ci:02}')
        bw,bh=(270,262) if not portrait else (650,295)
        bi=Image.new('RGBA',(bw,bh));bd=ImageDraw.Draw(bi)
        bd.rounded_rectangle((1,1,bw-2,bh-22),radius=24,fill='white',outline='#cadbd3',width=2)
        if not portrait:bd.polygon([(105,bh-24),(139,bh-2),(150,bh-24)],fill='white')
        else:bd.polygon([(3,145),(0,190),(32,163)],fill='white')
        bd.text((23,21),'DaBin',font=f(16 if not portrait else 24,True),fill=TEAL)
        bf=f(27 if not portrait else 40,True)
        bl=lines(bubble,bf,bw-46)
        if len(bl)*(bf.size+9)>bh-88:raise ValueError('Speech guide overflow '+bubble)
        for k,line in enumerate(bl):bd.text((23,58+k*(bf.size+9)),line,font=bf,fill=INK)
        save(bi,f'BUBBLE_{layout}_{ci:02}')
    # This is an instruction from the robot, not a redrawn app menu.
    bw,bh=(270,262) if not portrait else (650,295)
    bi=Image.new('RGBA',(bw,bh));bd=ImageDraw.Draw(bi)
    bd.rounded_rectangle((1,1,bw-2,bh-22),radius=24,fill='white',outline='#cadbd3',width=2)
    bf=f(27 if not portrait else 40,True)
    bd.text((23,21),'DaBin',font=f(16 if not portrait else 24,True),fill=TEAL)
    for k,line in enumerate(lines('More → Back up archive…',bf,bw-46)):
        bd.text((23,58+k*(bf.size+9)),line,font=bf,fill=INK)
    save(bi,'BUBBLE_'+layout+'_BACKUP')
# Original artwork gives the talking mouth its exact native color and shape.
# Only this small face patch changes during speech. No new robot is drawn.
hungry=Image.open(ASSETS/'DABIN__ROBOT__HUNGRY.png').convert('RGBA')
save(hungry.crop((345,303,483,395)),'MOUTH_OPEN')
cur=Image.new('RGBA',(60,74)); d=ImageDraw.Draw(cur)
d.polygon([(7,4),(7,60),(20,45),(30,68),(40,63),(29,42),(48,41)],fill='white',outline='#243a3c',width=3)
save(cur,'CURSOR')
ring=Image.new('RGBA',(160,160)); d=ImageDraw.Draw(ring)
d.ellipse((10,10,150,150),fill=(235,126,83,24),outline=(220,112,73,245),width=7)
save(ring,'CLICK_RING')
example=Image.new('RGBA',(650,60)); d=ImageDraw.Draw(example)
d.rounded_rectangle((0,0,649,59),radius=15,fill='#e6eee8')
d.text((20,12),'Timer-end example · task stays open',font=f(28,True),fill=INK)
save(example,'TIMER_EXAMPLE')
bar=Image.new('RGBA',(1500,6),TEAL);save(bar,'PROGRESS')
print(json.dumps({'textures':len(list(TEX.glob('*.png'))),'chapters':len(EDIT['chapters']),'ui_pixels':'exact native'}))
