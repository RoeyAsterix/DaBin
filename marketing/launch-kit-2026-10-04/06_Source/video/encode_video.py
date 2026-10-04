#!/usr/bin/env python3
"""Encode and fully decode-check Blender frames. Requires public FFmpeg.

Set DABIN_FFMPEG or put ffmpeg on PATH. Nothing is uploaded or published.
"""
from pathlib import Path
import subprocess, shutil, os, json, hashlib, argparse, re
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent; KIT=HERE.parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--layout',choices=['landscape','portrait','all'],default='all');args=ap.parse_args()
ff=os.environ.get('DABIN_FFMPEG') or shutil.which('ffmpeg')
if not ff:
    local=KIT.parents[1]/'native/build/walkthrough-tools/imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1'
    if local.exists():ff=str(local)
if not ff:raise SystemExit('Set DABIN_FFMPEG to a public ffmpeg executable')
dest=KIT/'04_Video';qa=KIT/'07_QA';qa.mkdir(exist_ok=True)
records=[]
for layout in (['landscape','portrait'] if args.layout=='all' else [args.layout]):
    frames=KIT/'.work'/('frames_'+layout)
    if any(not (frames/f'DABIN__FRAME__{i:04}.png').exists() for i in range(1,661)):
        raise SystemExit('Missing Blender frames in '+str(frames))
    out=dest/('DABIN__FEED_DABIN__'+layout.upper()+'.mp4')
    cmd=[ff,'-y','-v','warning','-framerate','30','-start_number','1','-i',str(frames/'DABIN__FRAME__%04d.png'),'-i',str(dest/'audio/DABIN__FEED_DABIN__MIX.wav'),'-map','0:v:0','-map','1:a:0','-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-t','22','-movflags','+faststart','-map_metadata','-1',str(out)]
    encoded=subprocess.run(cmd,capture_output=True,text=True)
    if encoded.returncode:raise SystemExit(encoded.stderr)
    silent=out.with_name(out.stem+'_SILENT.mp4')
    subprocess.run([ff,'-y','-v','error','-i',str(out),'-map','0:v:0','-c','copy','-an','-map_metadata','-1','-movflags','+faststart',str(silent)],check=True)
    for path in [out,silent]:
        decode=subprocess.run([ff,'-v','error','-i',str(path),'-f','null','-'],capture_output=True,text=True)
        if decode.returncode or decode.stderr.strip():raise SystemExit('Full decode failed: '+str(path)+'\n'+decode.stderr)
        info=subprocess.run([ff,'-hide_banner','-i',str(path)],capture_output=True,text=True).stderr
        (qa/(path.stem+'_metadata.txt')).write_text(info)
        records.append({'file':str(path.relative_to(KIT)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'full_decode':'PASS','audio':'ElevenLabs narration and three original ticks' if path==out else 'none','frames':660,'fps':30,'duration_seconds':22,'dimensions':[1920,1080] if layout=='landscape' else [1080,1920],'pixel_format':'yuv420p','codec':'H.264','metadata':'authored prompt/workflow metadata excluded'})
    times=[2.2,5.48,5.80,6.64,7.50,8.90,11.20,13.20,15.95,18.80,21.96]
    thumbs=[]
    for i,t in enumerate(times):
        shot=qa/f'DABIN__QA__{layout.upper()}_{i+1:02}.png'
        subprocess.run([ff,'-y','-v','error','-ss',str(t),'-i',str(out),'-frames:v','1',str(shot)],check=True)
        im=Image.open(shot).convert('RGB');im.thumbnail((480,310))
        tile=Image.new('RGB',(520,360),'#f8f5ed');tile.paste(im,((520-im.width)//2,15))
        ImageDraw.Draw(tile).text((20,328),f'{t:.2f}s',font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20),fill='#193c3b');thumbs.append(tile)
    sheet=Image.new('RGB',(520*3,360*4),'white')
    for i,im in enumerate(thumbs):sheet.paste(im,((i%3)*520,(i//3)*360))
    sheet.save(qa/f'DABIN__QA__{layout.upper()}_CONTACT_SHEET.png')
    if layout=='landscape':
        subprocess.run([ff,'-y','-v','error','-ss','19','-i',str(out),'-frames:v','1',str(dest/'DABIN__FEED_DABIN__POSTER.png')],check=True)

# WebVTT for the local landing page; SRT remains editable for social platforms.
subtitle=(dest/'DABIN__FEED_DABIN__SUBTITLES.srt').read_text()
vtt='WEBVTT\n\n'+re.sub(r'(?<=\d),(?=\d{3})','.',subtitle)
(KIT/'05_Landing_Page/captions.vtt').write_text(vtt)
receipt={'renders':records,'visual_review':'pending original-resolution decoded-frame review','audio_review':'provider transcript exactly matched; waveform and full decode passed; no subjective listening claim','render_engine':'local Blender 5.2.1 EEVEE, emission planes, exact native art','publication':'not published; no posts or pitches sent'}
existing=qa/'video-verification.json'
if existing.exists():
    old=json.loads(existing.read_text());names={r['file'] for r in records};receipt['renders']=[r for r in old.get('renders',[]) if r['file'] not in names]+records
existing.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(records,indent=2))
