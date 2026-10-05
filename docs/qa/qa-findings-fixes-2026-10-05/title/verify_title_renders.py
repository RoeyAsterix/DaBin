#!/usr/bin/env python3
"""Read-only PNG verification of the native title's two visible line bands."""
from pathlib import Path
import argparse, hashlib, json, math, re
from PIL import Image
p=argparse.ArgumentParser()
p.add_argument('--renders',type=Path)
p.add_argument('--baseline-probe-output',type=Path)
p.add_argument('--baseline-only',action='store_true')
p.add_argument('--report',type=Path,required=True)
a=p.parse_args()
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
def measure(path,frame,theme,scale=2):
 image=Image.open(path).convert('RGBA')
 x0=max(0,math.ceil(frame['x']*scale)+2);y0=max(0,math.ceil(frame['y']*scale)+2)
 x1=min(image.width,math.floor((frame['x']+frame['width'])*scale)-2)
 y1=min(image.height,math.floor((frame['y']+frame['height'])*scale)-2)
 assert x1>x0 and y1>y0
 foreground=(235,234,237) if theme=='dark' else (43,39,49)
 rows=[]
 for y in range(y0,y1):
  count=0
  for x in range(x0,x1):
   color=image.getpixel((x,y))
   if color[3]>50 and max(abs(color[i]-foreground[i]) for i in range(3))<64:count+=1
  rows.append(count)
 middle=len(rows)//2
 first,second=rows[:middle],rows[middle:]
 return {'file':str(path),'sha256':sha(path),'imagePixels':[image.width,image.height],
  'titleFrameTopLeft':frame,'cropPixels':[x0,y0,x1,y1],'theme':theme,
  'firstLineForegroundPixels':sum(first),'secondLineForegroundPixels':sum(second),
  'firstLineInkRows':sum(c>=10 for c in first),'secondLineInkRows':sum(c>=10 for c in second),
  'twoLinesPainted':sum(first)>40 and sum(second)>40 and sum(c>=10 for c in first)>=4 and sum(c>=10 for c in second)>=4}
report={'scope':'Read-only actual full-Board raster at native field geometry; no GUI launch or image modification','candidate':[]}
if a.baseline_probe_output:
 ready=json.loads((a.baseline_probe_output/'launch-ready.json').read_text())
 field=next(f for f in ready['nativeEditableFields'] if f['fullFixtureTitle'])
 rect=lambda text:[float(v) for v in re.findall(r'-?\d+(?:\.\d+)?',text)]
 fx,fy,fw,fh=rect(field['frame']);wx,wy,_,_=rect(ready['windowFrame'])
 frame={'x':fx-wx,'y':ready['height']-(fy-wy+fh),'width':fw,'height':fh}
 report['baseline']=measure(a.baseline_probe_output/'cache-display-visible-window@2x.png',frame,'light')
 report['baseline']['defectReproduced']=report['baseline']['firstLineForegroundPixels']>40 and report['baseline']['secondLineForegroundPixels']<=40
if not a.baseline_only:
 if a.renders is None:p.error('--renders required for candidate verification')
 native_report=a.renders/'native-task-plan-report.json';data=json.loads(native_report.read_text())
 fixtures=[f for f in data['fixtures'] if f.get('context')=='unfocused-title-raster']
 assert len(fixtures)==2 and {f['zoom'] for f in fixtures}=={1,2}
 report['nativeInteractionReport']={'file':str(native_report),'sha256':sha(native_report),'checks':data['checks']}
 for fixture in fixtures:
  assert fixture['completeTitleRetained'] and fixture['titleFrameTopLeft']['height']<=fixture['lineHeight']*2+4.5
  measured=measure(a.renders/fixture['file'],fixture['titleFrameTopLeft'],fixture['theme'],fixture['pixelScale'])
  measured['zoom']=fixture['zoom'];report['candidate'].append(measured)
 report['status']='passed' if all(f['twoLinesPainted'] for f in report['candidate']) else 'failed-second-line-not-painted'
 if 'baseline' in report and not report['baseline']['defectReproduced']:report['status']='failed-baseline-not-reproduced'
else:
 report['status']='baseline-defect-reproduced' if report.get('baseline',{}).get('defectReproduced') else 'failed-baseline-not-reproduced'
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(0 if report['status'] in ['passed','baseline-defect-reproduced'] else 1)
