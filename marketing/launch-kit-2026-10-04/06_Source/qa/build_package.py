#!/usr/bin/env python3
"""Validate local kit references and build a CRC-tested ZIP with SHA256 inventory."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlparse,unquote
import hashlib,json,zipfile,re
from PIL import Image

KIT=Path(__file__).resolve().parents[2]
ZIP=KIT.parent/'DABIN__MARKETING_PACKAGE__2026-10-04.zip'
EXCLUDE={'.work','.build','__pycache__','.DS_Store'}
def included(p):
    r=p.relative_to(KIT)
    return p.is_file() and not any(part in EXCLUDE for part in r.parts) and p.suffix not in ['.blend1','.pyc'] and p.name not in ['SHA256_MANIFEST.json']
files=sorted(p for p in KIT.rglob('*') if included(p))
class Refs(HTMLParser):
    def __init__(self):super().__init__();self.refs=[]
    def handle_starttag(self,tag,attrs):
        for k,v in attrs:
            if k in ('href','src','poster') and v:self.refs.append(v)
missing=[];links=0;images=0;jsons=0
for p in files:
    if p.is_symlink():raise SystemExit('Unexpected symlink '+str(p))
    if p.suffix=='.html':
        refs=Refs();refs.feed(p.read_text())
        for ref in refs.refs:
            url=urlparse(ref)
            if url.scheme or url.netloc or not url.path or '[' in ref:continue
            links+=1
            target=(p.parent/unquote(url.path)).resolve()
            if not target.exists():missing.append({'page':str(p.relative_to(KIT)),'target':ref})
            elif KIT.resolve() not in target.parents:raise SystemExit('External local reference '+str(target))
    elif p.suffix=='.json':json.loads(p.read_text());jsons+=1
    elif p.suffix.lower()=='.png':
        with Image.open(p) as im:im.verify()
        images+=1
if missing:raise SystemExit('Missing local links:\n'+json.dumps(missing,indent=2))
required=['START_HERE.html','01_Launch_Playbook/DaBin_Launch_Guide.pdf','01_Launch_Playbook/30_Day_Calendar.json','02_Copy/Creator_Outreach_Templates_UNSENT.txt','03_Graphics/DABIN__SOCIAL__LANDSCAPE_1200x630.png','04_Video/DABIN__FEED_DABIN__LANDSCAPE.mp4','04_Video/DABIN__FEED_DABIN__PORTRAIT.mp4','05_Landing_Page/index.html','06_Source/video/DABIN__FEED_DABIN__LANDSCAPE.blend','06_Source/video/DABIN__FEED_DABIN__PORTRAIT.blend']
assert all((KIT/f).exists() for f in required)
manifest={'package':'DaBin Marketing Package','prepared_date':'2026-10-04','publication':'Prepared locally; not published or sent','validation':{'local_html_references':links,'broken_local_references':0,'decoded_png_files':images,'parsed_json_files':jsons,'required_outputs':'PASS'},'files':[{'path':str(p.relative_to(KIT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
(KIT/'SHA256_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
files.append(KIT/'SHA256_MANIFEST.json')
with zipfile.ZipFile(ZIP,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
    for p in files:z.write(p,'DaBin-Marketing-Package/'+str(p.relative_to(KIT)))
with zipfile.ZipFile(ZIP) as z:
    if z.testzip():raise SystemExit('ZIP CRC failed')
    names=z.namelist()
    for rel in required:assert 'DaBin-Marketing-Package/'+rel in names
    for p in files:
        data=z.read('DaBin-Marketing-Package/'+str(p.relative_to(KIT)))
        if hashlib.sha256(data).digest()!=hashlib.sha256(p.read_bytes()).digest():raise SystemExit('ZIP byte parity failed')
sha=hashlib.sha256(ZIP.read_bytes()).hexdigest()
ZIP.with_suffix('.zip.sha256').write_text(sha+'  '+ZIP.name+'\n')
print(json.dumps({'zip':str(ZIP),'file_count':len(files),'zip_bytes':ZIP.stat().st_size,'sha256':sha,'validation':manifest['validation'],'zip_crc':'PASS','zip_byte_parity':'PASS'},indent=2))
