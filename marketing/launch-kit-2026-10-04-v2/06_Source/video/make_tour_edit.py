#!/usr/bin/env python3
"""Build a voice-aligned edit, adding reading time only at spoken gaps."""
from pathlib import Path
import json,wave,re
import numpy as np

HERE=Path(__file__).resolve().parent; KIT=HERE.parents[1]
VOICE=HERE.parent/'voice'; AUDIO=KIT/'04_Video/audio'
pauses=[(14.3,.7),(24.54,1.1),(25.7,.9),(29.5,.5),(42.95,.8),(49.9,1.6),(53.9,.8),(67.05,.4),(68.9,.6),(70.33,.5),(73.4,1.0)]
intro=.5;tail=1.8
def t(sec):return round(sec+intro+sum(length for at,length in pauses if sec>=at),4)
with wave.open(str(AUDIO/'DABIN__UI_TOUR__NARRATION.wav')) as r:
    rate=r.getframerate();assert r.getnchannels()==1 and r.getsampwidth()==2
    voice=np.frombuffer(r.readframes(r.getnframes()),dtype='<i2').astype(np.float64)
parts=[np.zeros(round(intro*rate))];last=0
for at,length in pauses:
    bound=round(at*rate);parts.extend([voice[last:bound],np.zeros(round(length*rate))]);last=bound
parts.extend([voice[last:],np.zeros(round(tail*rate))])
out=np.concatenate(parts)*.75
# Quiet original soft taps at editorial action changes. Narration stays foremost.
tap_times=[t(4.8),t(6.8),t(10.3),t(13.7),t(20.5),t(24.7),t(30.1),t(35),t(41.2),t(50.3),t(52.5),t(65.8),t(68),t(73.5)]
for at in tap_times:
    n=round(rate*.065);u=np.arange(n)/rate
    pulse=160*np.sin(2*np.pi*(1100-2300*u)*u)*np.sin(np.pi*np.arange(n)/n)**2
    st=round(at*rate);out[st:st+n]+=pulse
out=np.rint(out).astype('<i2')
duration=round(len(out)/rate*30)/30
pad=round(duration*rate)-len(out)
if pad>0:out=np.pad(out,(0,pad))
elif pad<0:out=out[:pad]
with wave.open(str(AUDIO/'DABIN__UI_TOUR__MIX.wav'),'wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(out.tobytes())
spec=[
 ('Keep the screenshot.','Drop it here.',0,5.52),
 ('Catch the link. Save the thought.','Before it escapes.',5.52,11.3),
 ('Save first. Sort when you’re ready.','Save first. Sort later.',11.3,18.38),
 ('Bring a project together.','One project. Useful bits close.',18.38,24.76),
 ('Keep the handy bits close.','The handy little things.',24.76,32.3),
 ('Find words inside saved images.','Try “riverside”.',32.3,41.08),
 ('Narrow the search.','Just this project. Just images.',41.08,43.62),
 ('Give that idea a next step.','Give it a next step.',43.62,50.28),
 ('Plan today.','This is the plan.',50.28,51.98),
 ('One task. A little focus.','Start. Pause. Reset.',51.98,58.82),
 ('Automatic capture. Your choice.','You choose. You can pause.',58.82,67.66),
 ('Take the project with you.','Keep a copy where you choose.',67.66,69.18),
 ('Back up. Bring a capture back.','That one wasn’t lost.',69.18,74.3),
 ('Your little local companion.','Free. Here when you need me.',74.3,83.2),
]
chapters=[{'id':i+1,'title':title,'bubble':bubble,'start':0 if i==0 else t(start),'end':duration if i==len(spec)-1 else t(end)} for i,(title,bubble,start,end) in enumerate(spec)]
# Source times refer to the unmodified natural take. Native ROI coordinates are
# pixels in2360x1404 source images, never an invented control layout.
specshots=[
 (0,4.6,'01_INBOX_EMPTY',[1180,702,2360],[710,420,1404],[1180,610]),
 (4.6,5.52,'02A_INBOX_IMAGE_CAPTURE',[1180,702,2360],[1160,660,1404],None),
 (5.52,7.35,'02B_INBOX_LINK_CAPTURE',[1180,700,2100],[1080,650,1404],[95,500]),
 (7.35,10.3,'02_INBOX_TYPED',[1180,400,2100],[1050,400,1404],[2180,420]),
 (10.3,11.3,'03_INBOX_SAVED',[1180,700,2100],[1180,700,1404],[880,910]),
 (11.3,13.45,'04_INBOX_DAY',[1180,400,2200],[1510,550,1404],[2130,275]),
 (13.45,14.86,'05_INBOX_WEEK',[1180,650,2300],[1640,630,1404],[2240,275]),
 (14.86,18.38,'03_INBOX_SAVED',[1180,720,2100],[1120,700,1404],[170,265]),
 (18.38,23.25,'06_STUDIO_COLLECTION',[1180,680,2250],[1640,720,1404],[1900,190]),
 (23.25,24.76,'07_STUDIO_NOTES',[1160,750,2000],[1190,750,1250],[1090,400]),
 (24.76,26.2,'08_NAMED_SNIPPETS',[1180,560,2000],[700,700,1300],[1250,230]),
 (26.2,30.06,'08A_CLIPBOARD_HISTORY',[1180,600,2100],[1180,700,1404],[1100,400]),
 (30.06,32.3,'09_SHELF',[1180,700,2200],[1590,680,1404],[1780,275]),
 (32.3,37.06,'10_OCR_SEARCH',[1180,580,2250],[900,630,1404],[300,170]),
 (37.06,41.08,'11_OCR_PREVIEW',[1250,750,2250],[1770,720,1180],[1780,900]),
 (41.08,43.62,'12_FILTERED_SEARCH',[1180,470,2150],[1050,600,1404],[420,240]),
 (43.62,47.7,'13_TASK_PLAN',[1180,800,2200],[1100,750,1404],[150,1110]),
 (47.7,50.28,'14_TASK_REPEAT_REMINDER',[1180,800,2200],[1100,790,1404],[950,935]),
 (50.28,51.98,'15_TODAY',[1180,760,2100],[1130,700,1300],[1180,610]),
 (51.98,53.5,'16_FOCUS_READY',[1180,890,2100],[1120,860,1320],[255,1110]),
 (53.5,56.62,'17_FOCUS_RUNNING',[1180,890,2100],[1120,860,1320],[280,1120]),
 (56.62,58.82,'15_TODAY',[1180,760,2100],[1120,800,1350],[1270,1090]),
 (58.82,65.4,'18_AUTO_CAPTURE_OFF',[1180,775,1800],[1180,790,1280],[750,695]),
 (65.4,67.66,'19_AUTO_CAPTURE_PAUSED',[1180,760,1900],[1120,790,1320],[790,855]),
 (67.66,69.18,'20_PROJECT_EXPORT',[1180,420,2300],[1750,650,1350],[2110,280]),
 (69.18,70.62,'20_PROJECT_EXPORT',[1180,550,2360],[1640,600,1350],[2160,110]),
 (70.62,73.4,'21_RECENTLY_DELETED',[1180,440,2250],[1190,540,1404],[75,570]),
 (73.4,74.3,'22_RESTORED',[1180,720,2300],[1740,730,1404],[1970,960]),
 (74.3,83.2,'22_RESTORED',[1180,720,2360],[1660,710,1404],None),
]
shots=[]
for i,(start,end,name,focus,pfocus,pointer) in enumerate(specshots):
    if name in ['02B_INBOX_LINK_CAPTURE','02_INBOX_TYPED','03_INBOX_SAVED','04_INBOX_DAY','05_INBOX_WEEK','06_STUDIO_COLLECTION','09_SHELF','10_OCR_SEARCH','11_OCR_PREVIEW','12_FILTERED_SEARCH','20_PROJECT_EXPORT','21_RECENTLY_DELETED']:
        focus=[1180,702,2360]
    portrait_rois={
        '02A_INBOX_IMAGE_CAPTURE':[1050,702,1404],
        '02B_INBOX_LINK_CAPTURE':[1050,702,1404],
        '02_INBOX_TYPED':[702,702,1404],
        '03_INBOX_SAVED':[702,702,1404],
        '04_INBOX_DAY':[1050,702,1404],
        '05_INBOX_WEEK':[1880,570,960],
        '07_STUDIO_NOTES':[1100,702,1404],
        '08_NAMED_SNIPPETS':[702,702,1404],
        '08A_CLIPBOARD_HISTORY':[702,702,1404],
        '09_SHELF':[1880,670,960],
        '10_OCR_SEARCH':[702,702,1404],
        '12_FILTERED_SEARCH':[702,702,1404],
        '13_TASK_PLAN':[702,702,1404],
        '14_TASK_REPEAT_REMINDER':[702,702,1404],
        '16_FOCUS_READY':[702,702,1404],
        '17_FOCUS_RUNNING':[702,702,1404],
        '18_AUTO_CAPTURE_OFF':[975,925,950],
        '19_AUTO_CAPTURE_PAUSED':[975,925,950],
        '21_RECENTLY_DELETED':[702,702,1404],
    }
    pfocus=portrait_rois.get(name,pfocus)
    if name in ['18_AUTO_CAPTURE_OFF','19_AUTO_CAPTURE_PAUSED']:focus=[1220,906,1600]
    if name in ['08_NAMED_SNIPPETS','08A_CLIPBOARD_HISTORY']:focus=[840.5,650,1681]
    if name=='22_RESTORED' and start<74.3:pfocus=[702,702,1404]
    targets={
      '02B_INBOX_LINK_CAPTURE':[110,501],
      '02_INBOX_TYPED':[2268,426],
      '04_INBOX_DAY':[2157,259],
      '05_INBOX_WEEK':[2266,259],
      '06_STUDIO_COLLECTION':[1943,188],
      '07_STUDIO_NOTES':[2033,287],
      '08_NAMED_SNIPPETS':[150,550],
      '08A_CLIPBOARD_HISTORY':[904,287],
      '09_SHELF':[1485,287],
      '10_OCR_SEARCH':[300,185],
      '12_FILTERED_SEARCH':[408,323],
      '13_TASK_PLAN':[552,1054],
      '14_TASK_REPEAT_REMINDER':[934,734],
      '15_TODAY':[660,704],
      '16_FOCUS_READY':[273,1042],
      '17_FOCUS_RUNNING':[273,1042],
      '18_AUTO_CAPTURE_OFF':[720,586],
      '19_AUTO_CAPTURE_PAUSED':[764,794],
      '20_PROJECT_EXPORT':[2162,110] if start>=69.18 else [2115,280],
      '21_RECENTLY_DELETED':[146,504],
      '22_RESTORED':[350,680] if start<74.3 else None,
    }
    pointer=targets.get(name,pointer)
    shots.append({'start':0 if i==0 else t(start),'end':duration if i==len(specshots)-1 else t(end),'asset':f'DABIN__UI__{name}.png','focus':focus,'portrait_focus':pfocus,'pointer':pointer})
edit={'title':'DaBin explains the UI','version':2,'fps':30,'duration_seconds':duration,'narration_seconds':83.2,'narration_offset_seconds':intro,'reading_pauses':[{'source_at':a,'seconds':b} for a,b in pauses],'chapters':chapters,'shots':shots,'editorial_disclosure':'Actual native view states with fictional data. Composed guide, cursor and transitions; not continuous input recording.','audio_peak_dbfs':round(float(20*np.log10(max(abs(out.min()),out.max())/32768)),2),'native_art':'Same source robot; mouth, blink and gaze derive from native artwork.'}
(HERE/'tour_edit.json').write_text(json.dumps(edit,indent=2)+'\n')
# Adjust subtitle timestamps only. No narration words or syllables are cut.
phrases=json.loads((VOICE/'narration_phrase_timings.json').read_text())['phrases']
def stamp(sec,sep=','):
    ms=round(sec*1000);h,ms=divmod(ms,3600000);m,ms=divmod(ms,60000);s,ms=divmod(ms,1000);return f'{h:02}:{m:02}:{s:02}{sep}{ms:03}'
srt=[];vtt=['WEBVTT\n']
for i,p in enumerate(phrases):
    srt.append(f'{i+1}\n{stamp(t(p["start"]))} --> {stamp(t(p["end"]))}\n{p["text"]}\n')
    vtt.append(f'{stamp(t(p["start"]),".")} --> {stamp(t(p["end"]),".")}\n{p["text"]}\n')
(KIT/'04_Video/DABIN__UI_TOUR__SUBTITLES.srt').write_text('\n'.join(srt))
(KIT/'05_Landing_Page/captions.vtt').write_text('\n'.join(vtt))
print(json.dumps({'duration_seconds':duration,'chapters':len(chapters),'shots':len(shots),'peak_dbfs':edit['audio_peak_dbfs'],'pauses_seconds':sum(b for a,b in pauses)}))
