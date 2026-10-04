#!/usr/bin/env python3
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageChops
import json,hashlib,re
HERE=Path(__file__).resolve().parent
BOUNDS=(98,315,1000,1043)
for p in sorted(HERE.glob('DABIN__ROBOT_CANVAS__*.png')):
 im=Image.open(p).convert('RGBA'); im.crop(BOUNDS).save(HERE/p.name.replace('ROBOT_CANVAS','ROBOT'))
for p in HERE.glob('DABIN__ROBOT__FOCUS_ALARM_CANVAS.png'):
 im=Image.open(p).convert('RGBA');im.crop(im.getchannel('A').getbbox()).save(HERE/'DABIN__ROBOT__FOCUS_ALARM.png')
# Preserve the exact production native face background when swapping only its mouth.
poses={n:Image.open(HERE/f'DABIN__ROBOT__{n}.png').convert('RGBA') for n in ['IDLE','HUNGRY','DELIGHTED']}
boxes=[ImageChops.difference(poses['IDLE'].convert('RGB'),poses[n].convert('RGB')).getbbox() for n in ['HUNGRY','DELIGHTED']]
b=(min(x[0] for x in boxes)-3,min(x[1] for x in boxes)-3,max(x[2] for x in boxes)+3,max(x[3] for x in boxes)+3)
for n,im in poses.items():
 out=Image.new('RGBA',im.size,(0,0,0,0));out.paste(im.crop(b),(b[0],b[1]));out.save(HERE/f'DABIN__MOUTH__{n}.png')
(HERE/'robot-alignment.json').write_text(json.dumps({'sourceCanvas':[1024,1248],'fixedCrop':list(BOUNDS),'robotSize':[902,728],'mouthPatchRect':list(b),'mouthPatchSize':[902,728],'method':'Existing semantic production native idle/open-mouth/smile poses. Patch retains exact native face pixels so old mouth is replaced cleanly, with no drawn or generated replacement.'},indent=2)+'\n')
files=sorted(p for p in HERE.glob('DABIN__UI__*.png') if re.match(r'DABIN__UI__\d{2}[A-Z]?_',p.name))
f=ImageFont.truetype('/System/Library/Fonts/SFNS.ttf',16)
cols=3;cw=560;ch=390;sheet=Image.new('RGB',(cols*cw,((len(files)+cols-1)//cols)*ch),'#E5E0D6')
for n,p in enumerate(files):
 im=Image.open(p).convert('RGB'); im.thumbnail((540,333),Image.Resampling.LANCZOS)
 x=(n%cols)*cw+(cw-im.width)//2;y=(n//cols)*ch+10
 sheet.paste(im,(x,y));ImageDraw.Draw(sheet).text(((n%cols)*cw+12,(n//cols)*ch+ch-33),p.name,font=f,fill='#24302E')
sheet.save(HERE/'DABIN__QA__V2_NATIVE_STATES.png')
print('Prepared',len(files),'actual UI states. Native mouth rect:',b)
