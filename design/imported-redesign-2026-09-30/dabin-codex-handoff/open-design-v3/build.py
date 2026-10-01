"""Build separate standalone screens from the editable shared component sources."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent.parent
SRC=ROOT/'open-design-v3'
pages=['inbox','today','workspace','clipboard','shelf','notes','activity','weekly','search','capture-detail','task-detail','new-note','new-task','reminder','export','settings','recently-deleted','backup','robot']
css=(SRC/'tokens.css').read_text()+'\n'+(SRC/'refinement.css').read_text()+'\n'+(SRC/'task-ui.css').read_text()+'\n'+(SRC/'provenance.css').read_text()+'\n'+(SRC/'project-picker.css').read_text()+'\n'+(SRC/'responsive.css').read_text()
js='\n'.join((SRC/f).read_text() for f in ['model.js','provenance.js','views.js','project-picker.js','responsive.js','task-ui.js','settings.js','interactions.js','events.js'])
for p in pages:
 html='<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+p.replace('-',' ').title()+' · DaBin</title><style>\n'+css+'\n</style></head><body data-page="'+p+'"><script>\n'+js+'\n</script></body></html>\n'
 (ROOT/(p+'.html')).write_text(html)
(SRC/'screen-index.json').write_text(json.dumps({'entry':'index.html','product_screens':pages,'fixture_date':'2026-09-30','native_baseline':'0.4.2 (53)'},indent=2))
print(f'Built {len(pages)} standalone product screens.')
