#!/usr/bin/env python3
"""Package reviewed DaBin submission assets without publishing them."""
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[2]
PACK=ROOT/'docs/app-store/submission-pack-0.4.31-86'
GUIDE=ROOT/'docs/DaBin-Quick-Guide.pdf'
QA=ROOT/'design/app-store-pack/qa'
receipt=json.loads((QA/'document-verification.json').read_text())
doc=PACK/'DaBin-App-Store-Content.docx'
assert hashlib.sha256(doc.read_bytes()).hexdigest()==receipt['documentSHA256']
reader=PdfReader(GUIDE)
guide_text='\n'.join(p.extract_text() for p in reader.pages)
assert '0.4.31' in guide_text and len(reader.pages)==2, 'Updated two-page guide required before packaging'
guide_qa=json.loads((ROOT/'design/onepager/qa/robot-guide-2026-10-04.json').read_text())
assert guide_qa['result']=='PASS'
assert hashlib.sha256(GUIDE.read_bytes()).hexdigest()==guide_qa['outputs']['docs/DaBin-Quick-Guide.pdf']
shutil.copy2(GUIDE, PACK/GUIDE.name)
shutil.copy2(ROOT/'docs/DaBin-Friendly-Copy.txt', PACK/'Copy/DaBin-Friendly-Copy.txt')
(PACK/'README.txt').write_text('''DABIN APP STORE CONTENT PACK
Version 0.4.31 (86) - 4 October 2026 - English US

START HERE
Open DaBin-App-Store-Content.docx for the listing fields, private review
walkthrough, three screenshot pages, privacy/declaration guidance, owner
fields, support FAQ, full privacy policy and Apple references.

DaBin-Quick-Guide.pdf is the updated two-page customer guide. The original
guide is preserved separately in the project design archive.

Screenshots/ contains the original 1440 x 900 RGB PNGs in upload order:
01 Inbox, 02 Projects, 03 Focus. Do not upload screenshots extracted from
the document. These native views use fictional data and verified release
source; compare them with the final distribution-signed app before upload.

Copy/ contains individual copy-and-paste text fields, reviewer notes,
support-page copy, the exact bundled privacy policy, current metadata JSON
and the guide's readable copy. Support/contact placeholders must be filled.
What's New is for a subsequent App Store version only, not a first version.

Assets/ contains the current 1024-pixel PNG app icon and the bundled ICNS.
The Mac app icon is supplied through the app build. No App Store preview
video or signed application package is included.

OWNER FIELDS
Confirm the legal rights holder/copyright, app record and SKU, public support
page/contact, private review contact, pricing, territories, release method,
license, rights, age rating, privacy, encryption and EU trader declarations.
Keep private review contacts out of a public repository or website.

RELEASE STATUS
This is a prepared local content pack, not an App Store submission.
Publish the current policy and maintained support page; finish distribution
signing, package validation, signed-app acceptance and screenshot comparison
before uploading. Apple reviews the final binary and metadata.

manifest.json records the files and checksums. It excludes itself.
''')
source_manifest=json.loads((ROOT/'docs/app-store/screenshots/0.4.31-86/manifest.json').read_text())
manifest={'product':'DaBin','version':'0.4.31','build':'86','locale':'en-US',
          'status':'CONTENT_PREPARED_OWNER_FIELDS_AND_RELEASE_GATES_PENDING',
          'docxPages':13,'quickGuidePages':2,
          'screenshots':{'dimensions':[1440,900],'format':'PNG','mode':'RGB','alpha':False,'order':['Inbox','Projects','Focus'],'source':'Native production Store-channel views with fictional records','finalSignedAppComparison':'pending'},
          'sourceScreenshotHashes':{s['file']:s['sha256'] for s in source_manifest['screenshots']},
          'files':[]}
for path in sorted(PACK.rglob('*')):
    if path.is_file() and path.name!='manifest.json':
        manifest['files'].append({'file':str(path.relative_to(PACK)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(PACK/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
zip_path=ROOT/'output/DaBin-App-Store-Pack-0.4.31-86.zip'
zip_path.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for path in sorted(PACK.rglob('*')):
        if path.is_file():z.write(path,Path('DaBin-App-Store-Pack-0.4.31-86')/path.relative_to(PACK))
with zipfile.ZipFile(zip_path) as z:
    assert z.testzip() is None
    for entry in manifest['files']:
        name='DaBin-App-Store-Pack-0.4.31-86/'+entry['file']
        assert hashlib.sha256(z.read(name)).hexdigest()==entry['sha256']
print(json.dumps({'zip':str(zip_path),'bytes':zip_path.stat().st_size,'files':len(manifest['files'])+1,'guideSHA256':hashlib.sha256(GUIDE.read_bytes()).hexdigest()},indent=2))
