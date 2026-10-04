#!/usr/bin/env python3
"""Create code-authored title/card textures and the local narration mix.

No production UI is redrawn. Every UI texture is an exact native fixture render.
Run with the bundled Python (Pillow/numpy). Source assets are sibling ../assets.
"""
from pathlib import Path
import json, math, re, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1]
ASSETS = HERE.parent / 'assets'
TEX = HERE / 'textures'
TEX.mkdir(exist_ok=True)
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
INK = '#193c3b'; MUTED = '#577371'; TEAL = '#136c69'; CLAY = '#d87651'
PAPER = '#f8f5ed'

def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)

def text_image(name, text, size, color=INK, bold=True, width=None, center=False, pad=8):
    f = font(size, bold)
    lines = text.split('\n')
    measure = ImageDraw.Draw(Image.new('RGBA', (1,1)))
    w = width or int(max(measure.textlength(line, font=f) for line in lines) + pad*2)
    h = int(len(lines) * size * 1.16 + pad*2)
    im = Image.new('RGBA', (w,h))
    d = ImageDraw.Draw(im)
    for i,line in enumerate(lines):
        x = (w-measure.textlength(line, font=f))/2 if center else pad
        d.text((x, pad+i*size*1.16), line, font=f, fill=color, stroke_width=0)
    im.save(TEX / ('DABIN__TEXT__'+name+'.png'))

def pill(name,text,bg=TEAL,color='white',size=30):
    f = font(size,True)
    w = int(f.getlength(text)+66); h = size+42
    im = Image.new('RGBA',(w,h))
    ImageDraw.Draw(im).rounded_rectangle((0,0,w-1,h-1),radius=h/2,fill=bg)
    ImageDraw.Draw(im).text((33,15),text,font=f,fill=color)
    im.save(TEX / ('DABIN__PILL__'+name+'.png'))

def token(kind):
    im = Image.new('RGBA',(500,380))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((15,15,485,360),radius=28,fill='white',outline='#d3d9d1',width=3)
    d.rounded_rectangle((38,39,127,85),radius=14,fill='#dcece8')
    d.text((52,49),kind.upper(),font=font(21,True),fill=TEAL)
    if kind=='Link':
        d.text((42,118),'Studio inspiration',font=font(32,True),fill=INK)
        d.text((42,179),'example.com/studio',font=font(28),fill=MUTED)
        d.line((42,248,385,248),fill='#e2e6df',width=3)
        d.text((42,273),'Something worth keeping.',font=font(23),fill=MUTED)
    elif kind=='Note':
        d.text((42,113),'A palette idea',font=font(32,True),fill=INK)
        for i,line in enumerate(['Warm clay.','Deep teal.','Soft cream.']):
            d.text((42,169+i*44),line,font=font(28),fill=MUTED)
    else:
        src=Image.open(ASSETS/'DABIN__SAMPLE__STUDIO_REFERENCE.png').convert('RGBA')
        src.thumbnail((426,251),Image.Resampling.LANCZOS)
        im.alpha_composite(src,((500-src.width)//2,99))
    im.save(TEX/('DABIN__TOKEN__'+kind.upper()+'.png'))

def shadow(width,height,name):
    im=Image.new('RGBA',(width,height))
    d=ImageDraw.Draw(im)
    d.ellipse((30,18,width-30,height-18),fill=(20,45,40,32))
    im=im.filter(ImageFilter.GaussianBlur(16))
    im.save(TEX/('DABIN__SHADOW__'+name+'.png'))

def bg(w,h,name):
    im=Image.new('RGB',(w,h),PAPER)
    d=ImageDraw.Draw(im)
    if w>h:
        d.ellipse((w*.55,-h*.30,w*1.13,h*1.25),fill='#e1eee8')
        d.ellipse((w*.66,h*.65,w*1.12,h*1.46),fill='#eddfcf')
    else:
        d.ellipse((-w*.3,h*.27,w*1.3,h*1.04),fill='#e1eee8')
        d.ellipse((w*.45,h*.80,w*1.6,h*1.40),fill='#eddfcf')
    im.save(TEX/('DABIN__BACKDROP__'+name+'.png'))

bg(1920,1080,'LANDSCAPE'); bg(1080,1920,'PORTRAIT')
for kind in ['Link','Note','Image']: token(kind)
shadow(900,120,'ROBOT')
text_image('BRAND','DaBin',52)
text_image('FOR_MAC','for Mac',23,MUTED,False)
text_image('INTRO_L','A little robot.\nA useful habit.',94,width=850)
text_image('INTRO_P','A little robot.\nA useful habit.',91,width=970,center=True)
text_image('INTRO_SUB_L','For the useful bits of your day.',34,MUTED,False)
text_image('INTRO_SUB_P','For the useful bits of your day.',35,MUTED,False,width=990,center=True)
text_image('FEED_L','Feed DaBin.',96)
text_image('FEED_P','Feed DaBin.',100,width=1000,center=True)
text_image('FEED_SUB_L','A link. A note. An image.',34,MUTED,False)
text_image('FEED_SUB_P','A link. A note. An image.',40,MUTED,False,width=1000,center=True)
text_image('PROJECT_L','Keep a\nproject\ntogether.',70,width=510)
text_image('PROJECT_P','Keep a project\ntogether.',84,width=1000,center=True)
text_image('SEARCH_L','Find words\ninside saved\nimages.',63,width=535)
text_image('SEARCH_P','Find words inside\nsaved images.',79,width=1000,center=True)
text_image('SEARCH_NOTE_L','Local text recognition.',27,MUTED,False)
text_image('SEARCH_NOTE_P','Local text recognition.',36,MUTED,False,width=1000,center=True)
text_image('END_L','Save now.\nFind it later.',97,width=900)
text_image('END_P','Save now.\nFind it later.',105,width=1000,center=True)
text_image('TAG_L','Keep it on your Mac.',35,MUTED,False)
text_image('TAG_P','Keep it on your Mac.',43,MUTED,False,width=1000,center=True)
text_image('COMPAT_L','Apple Silicon  /  macOS 14 or later',24,MUTED,False)
text_image('COMPAT_P','Apple Silicon  /  macOS 14 or later',28,MUTED,False,width=1000,center=True)
text_image('UI_NOTE_L','Actual DaBin interface. Fictional example content.',20,MUTED,False)
text_image('UI_NOTE_P','Actual DaBin interface. Fictional examples.',25,MUTED,False,width=1000,center=True)
pill('FREE','Free')
pill('ACCOUNT','No account')
pill('LOCAL','Saved on your Mac')
pill('SUCCESS','Saved',bg='#dcece8',color=TEAL,size=31)
pill('CAPTURE','Drop something worth keeping',bg='#edf0e8',color=TEAL,size=28)

# Construct a source-aligned narration edit. Pauses give viewers time to read the
# two actual native interface states; no speech syllables are trimmed.
src=KIT/'04_Video/audio/DaBin_Feed_Narration_Paced_092.wav'
with wave.open(str(src)) as r:
    assert r.getnchannels()==1 and r.getsampwidth()==2
    rate=r.getframerate(); voice=np.frombuffer(r.readframes(r.getnframes()),dtype='<i2').astype(np.float64)
a=int(8.55*rate); b=int(10.70*rate)
mixed=np.concatenate([np.zeros(rate),voice[:a],np.zeros(rate),voice[a:b],np.zeros(int(1.5*rate)),voice[b:]])
length=22*rate
mixed=np.pad(mixed,(0,max(0,length-len(mixed))))[:length]*.94
# Three quiet original save ticks, synthesized here; no stock/music licensing.
for t in [5.98,6.92,7.88]:
    n=int(.085*rate); u=np.arange(n)/rate
    tone=800*np.sin(2*math.pi*(980+500*u)*u)*np.sin(math.pi*np.arange(n)/n)**2
    at=int(t*rate); mixed[at:at+n]+=tone
mixed=np.clip(np.rint(mixed),-32768,32767).astype('<i2')
out=KIT/'04_Video/audio/DABIN__FEED_DABIN__MIX.wav'
with wave.open(str(out),'wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(mixed.tobytes())

def seconds(s):
    h,m,rest=s.split(':');sec,ms=rest.split(',')
    return int(h)*3600+int(m)*60+int(sec)+int(ms)/1000
def stamp(t):
    ms=int(round(t*1000));return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
original=(KIT/'04_Video/DaBin_Feed_Narration_Paced_092_Offset_1s.srt').read_text()
parts=[]
for block in original.strip().split('\n\n'):
    lines=block.splitlines();num=int(lines[0]);st,en=lines[1].split(' --> ')
    shift=(1.0 if num>=7 else 0)+(1.5 if num>=8 else 0)
    parts.append('\n'.join([str(num),stamp(seconds(st)+shift)+' --> '+stamp(seconds(en)+shift),*lines[2:]]))
(KIT/'04_Video/DABIN__FEED_DABIN__SUBTITLES.srt').write_text('\n\n'.join(parts)+'\n')

story={
 'title':'Feed DaBin','duration_seconds':22,'fps':30,
 'scenes':[
   {'time':[0,5.1],'action':'Exact current native robot enters with gentle settle; promise'},
   {'time':[5.1,8.25],'action':'Fictional link/note/palette-image tokens fly into exact hungry robot, then saved reaction'},
   {'time':[8.25,10.9],'action':'Actual native Studio refresh project (fictional captures)'},
   {'time':[10.9,14.3],'action':'Actual native riverside query and OCR result; saved content only'},
   {'time':[14.3,22],'action':'Save now / Find it later; Free / No account / Saved on your Mac appear with voice'}],
 'audio':{'provider':'ElevenLabs','selected_take':2,'pace':.92,'intro_delay_seconds':1,'added_pauses_seconds':[1,1.5],'music':'none','effects':'three original code-generated quiet ticks'},
 'disclosure':'Editorial promo, not continuous screen recording. Native product UI and real saved-content OCR are captured in isolated fixtures. Flying tokens and pointer highlights are editorial animation.',
 'captions':'Separate SRT timed using measured waveform phrase boundaries; text recognition verified; timing remains editorial estimates.'}
(HERE/'storyboard.json').write_text(json.dumps(story,indent=2)+'\n')
print('Prepared textures, 22-second mix, SRT and storyboard')
