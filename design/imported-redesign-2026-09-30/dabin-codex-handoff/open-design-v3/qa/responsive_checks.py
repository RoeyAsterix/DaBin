"""Executed by verify.py. Geometry and behavior checks, NOT rendered layout checks."""
c=context('workspace')
sizes=[(360,640),(390,844),(400,480),(430,360),(600,480),(768,1024),(1024,768),(1440,900),(1920,1080)]
for width,height in sizes:
 viewport={'left':0,'top':0,'width':width,'height':height}
 rect={'left':900,'top':650,'width':980,'height':820}
 out=json.loads(c.run('JSON.stringify(fitWindowRect('+json.dumps(rect)+','+json.dumps(viewport)+'))'))
 check(f'Viewport geometry {width}×{height}: window stays reachable',out['left']>=0 and out['top']>=0 and out['left']+out['width']<=width and out['top']+out['height']<=height)
 for label,anchor in [('top',{'left':8,'top':12,'bottom':48}),('bottom',{'left':width-90,'top':height-64,'bottom':height-24})]:
  out=json.loads(c.run('JSON.stringify(projectPanelRect('+json.dumps(anchor)+', {width:332,height:410},'+json.dumps(viewport)+'))'))
  check(f'Viewport geometry {width}×{height}: {label} project panel stays reachable',out['left']>=12 and out['top']>=12 and out['left']+out['width']<=width-12 and out['top']+out['height']<=height-12)
check('Panel flips above low trigger instead of obscuring it',c.run('projectPanelRect({left:40,top:500,bottom:536},{width:332,height:200},{left:0,top:0,width:768,height:600}).top===292')=='true')
check('Keyboard viewport offset bounds',c.run('(()=>{const r=projectPanelRect({left:300,top:160,bottom:204},{width:332,height:410},{left:20,top:100,width:360,height:260});return r.left>=32&&r.top>=112&&r.left+r.width<=368&&r.top+r.height<=348})()')=='true')
checks={
 'Project heading uses selected project':"state.project='Northstar Studio';projectHeading().includes('Northstar Studio')",
 'Project search is case insensitive':"matchingProjects(' northSTAR ').some(p=>p.name==='Northstar Studio')",
 'No-result search returns no options':"matchingProjects('zzz-no-such-project').length===0",
 'Empty project names rejected':"!!projectNameError('')",
 'Duplicate project names rejected':"!!projectNameError(state.projects[0].toUpperCase())",
 'All projects cannot be confused with a named project':"!!projectNameError('All projects')",
 'Long project names rejected':"!!projectNameError('x'.repeat(181))",
 'Long valid heading safely escapes markup':"state.project='<script> & '+ 'Long project '.repeat(12);!projectHeading().includes('<script>')&&projectHeading().includes('&lt;script&gt;')",
 'Unknown project selection is rejected without changing state':"const prev=state.project;!commitProjectSelection('missing-project')&&state.project===prev",
}
for name,code in checks.items():
 try:check(name,c.run(code)=='true')
 except Exception as e:check(name,False,str(e))
# A minimal DOM fixture exercises persistence and failure handling in real picker code.
c.run("$('#project-switcher').hidePopover=()=>{};window.pickerRenderCount=0;render=()=>window.pickerRenderCount++;")
for name,code in {
 'Create project selects and saves it':"commitProjectSelection('QA project',true)&&state.projects.includes('QA project')&&state.project==='QA project'&&window.pickerRenderCount===1",
 'Stored project selection survives reload':"JSON.parse(storage[KEY]).project==='QA project'",
 'Failed project save keeps current selection':"(()=>{failSave=true;const before=JSON.stringify(state);const ok=commitProjectSelection('Unsaved project',true);failSave=false;return !ok&&JSON.stringify(state)===before})()",
 'Same project cannot be created twice':"!commitProjectSelection('QA project',true)&&state.projects.filter(p=>p==='QA project').length===1",
}.items():
 try:check(name,c.run(code)=='true')
 except Exception as e:check(name,False,str(e))
# Check generated scripts against all source modules: robot-only edits must not recur.
expected='\n'.join((SRC/n).read_text() for n in names)
for page in pages:
 html=(ROOT/(page+'.html')).read_text()
 check('Shared build matches source: '+page,expected in html)
 check('Project picker and responsive layer included: '+page,'function bindProjectSwitcher()' in html and 'function fitWindowRect(' in html and 'max-height:calc(100dvh - 24px)' in html)
