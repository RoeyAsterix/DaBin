import fs from 'node:fs';
import nodePath from 'node:path';

// These are exact production-view rasters. Only cursor/guide motion is editorial.
const W=1920, H=1080, FPS=30, END=59;
const APP={x:48,y:32,width:1380,height:1380*560/760};
const S=APP.width/760;
const point=(x,y)=>[APP.x+x*S,APP.y+y*S];
const C={bg:'#F5F1F8',ink:'#392C48',purple:'#9D77B9',paper:'#FFFFFF',line:'#C6B0D8'};
const states=[
  [0,10.9,'01-daily-before'],[10.9,13.1,'03-capture-success'],
  [13.1,15.5,'04-daily-captured'],[15.5,17.7,'05-daily-files'],
  [17.7,18.8,'04-daily-captured'],[18.8,25.5,'06-weekly'],
  [25.5,27,'08-search-empty'],[27,27.5,'09-search-launch'],
  [27.5,28,'10-search-launch-check'],[28,33,'11-search-result'],
  [33,34.8,'12-detail-before'],[34.8,35.4,'13-comment-empty'],
  [35.4,36.4,'14-comment-draft'],[36.4,37.8,'15-comment-saved'],
  [37.8,38.8,'16-before-task'],[38.8,40.1,'17-task-created'],
  [40.1,41,'18-daily-task'],[41,42.1,'19-daily-completed'],
  [42.1,46.3,'20-settings-auto-off'],[46.3,49.8,'21-settings-local'],
  [49.8,50.7,'25-daily-final'],[50.7,55.6,'22-weekly-export'],
  [55.6,END,'25-daily-final']
];
const lineBreaks={
  'Drop your day here.':'Drop your day\nhere.',
  'I’ll save your launch plan.':'I’ll save your\nlaunch plan.',
  'Right here, in today.':'Right here,\nin today.',
  'Only the days you used.':'Only the days\nyou used.',
  'Search inside your documents.':'Search inside\nyour documents.',
  'Give it a next step.':'Give it a\nnext step.',
  'Auto Capture starts off.':'Auto Capture\nstarts off.',
  'Saved and searched on your Mac.':'Saved and searched\non your Mac.',
  'Take your day or week.':'Take your day\nor week.',
  'Your day, organized.':'Your day,\norganized.'
};

export default async ({project,frame,media,path,rect,text})=>{
  const root=process.env.DABIN_REPO_ROOT||process.cwd();
  const assets=process.env.DABIN_WALKTHROUGH_ASSETS||nodePath.join(root,'native/build/qa/walkthrough');
  const voices=process.env.DABIN_WALKTHROUGH_AUDIO||nodePath.join(root,'native/build/qa/walkthrough-audio');
  const narration=JSON.parse(fs.readFileSync(nodePath.join(root,'design/walkthrough/assets/narration.json'),'utf8'));
  const p=await project({dir:process.env.DABIN_VIDEO_PROJECT_DIR||nodePath.join(root,'native/build/DaBinAppWalkthrough'),size:`${W}x${H}`,fps:FPS,background:C.bg});
  const cache=new Map();
  async function asset(name){
    if(!cache.has(name)) cache.set(name,await p.add(nodePath.join(assets,`${name}@2x.png`)));
    return cache.get(name);
  }
  const anim=(property,keys)=>({property,keyframes:keys.map(([at,value,easing])=>({at,value,easing:easing||'smooth'}))});
  const native=(file,x,y,width,height,extra={})=>media({file,x,y,width,height,fit:'contain',...extra});
  p.compose([
    rect({width:W,height:H,fill:{kind:'linear',angle:24,stops:[{offset:0,color:'#F8F5FA'},{offset:1,color:'#E6DAEF'}]}}),
    text('FICTIONAL DEMO',{x:1506,y:1038,width:348,height:22,fontFamily:'DM Sans',fontSize:15,fontWeight:500,letterSpacing:2,color:'#806990',align:'center'})
  ],{at:0,dur:END,name:'Quiet desktop and fictional demo disclosure'});
  for(const [at,end,name] of states){
    const width=name.includes('weekly')?APP.width*780/760:APP.width;
    const file=await asset(name);
    const ui=native(file,APP.x,APP.y,width,APP.height,{shadow:{x:0,y:8,blur:25,color:'#42265722'}});
    // Reveal the real weekly image horizontally, echoing its native unfolding.
    const layer=name==='06-weekly'?frame({x:0,y:0,width:W,height:H,layout:'none',clip:true,
      animate:[anim('opacity',[[0,0.6],[0.3,1]]),anim('scaleX',[[0,0.96],[0.45,1]])]},[ui]):ui;
    p.compose(layer,
      {at,dur:end-at,name:`Production UI • ${name}`});
  }
  const menu=(name,pos,width,height,at,dur)=>asset(name).then(file=>p.compose(
    native(file,...point(...pos),width*S,height*S,{shadow:{x:0,y:8,blur:20,color:'#00000055'}}),
    {at,dur,name:`Production popover • ${name}`}));
  await menu('07-week-search-menu',[268,76],258,174,24.1,1.4);
  await menu('23-export-menu',[259,76],262,286,51.45,4.15);

  const robotX=1595,robotY=825,robotW=174,robotH=212.0625;
  for(const [at,end,name] of [[0,4.8,'robot-idle'],[4.8,6.2,'robot-curious'],[6.2,7.1,'robot-hungry'],[7.1,9.2,'robot-digesting'],[9.2,11,'robot-success'],[11,END,'robot-idle']]){
    const animate=at===0?[anim('offsetY',[[0,44],[0.8,-4],[1.1,0]]),anim('opacity',[[0,0],[0.5,1]])]:name==='robot-digesting'?[anim('rotation',[[0,-3],[0.25,4],[0.5,-3],[0.8,3],[1.1,-2],[1.5,2],[end-at,0]]),anim('scaleY',[[0,1],[0.2,0.90],[0.4,1.06],[0.7,0.96],[1,1.03],[end-at,1]])]:[];
    p.compose(frame({x:robotX,y:robotY,width:robotW,height:robotH,layout:'none',origin:'center',animate},[native(await asset(name),0,0,robotW,robotH)]),{at,dur:end-at,name:`Native guide • ${name}`});
  }
  p.compose(frame({x:1535,y:360,width:292,height:136,layout:'none',origin:'center',animate:[
    anim('offsetX',[[0,0],[4.3,0],[6.6,5],[7.25,5]]),anim('offsetY',[[0,0],[4.3,0],[6.6,492],[7.25,510]]),
    anim('scale',[[0,1],[6.5,1],[7.25,0.04]]),anim('opacity',[[0,1],[7,1],[7.25,0]])
  ]},[native(await asset('fixture-file-icon'),104,0,84,92),text('Launch-plan.pdf',{x:0,y:102,width:292,height:34,fontFamily:'DM Sans',fontSize:25,fontWeight:600,align:'center',color:C.ink})]),
    {at:0,dur:7.25,name:'Simulated PDF drag between verified production states'});

  for(const line of narration){
    const dur=line.until-line.at;
    p.compose(frame({x:1496,y:line.at<11?160:653,width:380,height:148,layout:'none'},[
      path({d:'M 160 140 L 180 164 L 202 140 Z',width:380,height:164,fill:C.paper,stroke:{width:2,color:C.line}}),
      rect({width:380,height:148,radius:28,fill:C.paper,strokeWidth:2,strokeColor:C.line,shadow:{x:0,y:6,blur:16,color:'#4F365719'}}),
      text(lineBreaks[line.text]||line.text,{x:22,y:29,width:336,height:94,fontFamily:'DM Sans',fontSize:31,fontWeight:600,lineHeight:1.17,align:'center',color:C.ink})
    ]),{at:line.at,dur,name:`Robot speech • ${line.text}`});
    const voiceFile=nodePath.join(voices,line.file);
    if(!fs.existsSync(voiceFile)) throw new Error(`Required narration missing: ${voiceFile}`);
    const voice=await p.add(voiceFile);
    p.cut(voice,{at:line.at,from:0,dur:Math.min(voice.duration,dur)});
  }
  const P={files:point(404,90),all:point(260,90),weekly:point(244,22),daily:point(228,22),search:point(330,56),export:point(390,56),settings:point(500,56),back:point(28,28)};
  const moves=[
    [0,1800,310],[3.7,1690,390],[4.3,1690,390],[6.6,1694,890],[8.7,1780,892],[9.9,1685,900],[10.65,1685,900],[11.4,...point(370,175)],
    [14.9,...P.files],[15.5,...P.files],[17.3,...P.all],[17.7,...P.all],[18.3,...P.weekly],[18.8,...P.weekly],[20.1,...point(645,245)],
    [23.6,...P.search],[24.1,...P.search],[25,...point(398,210)],[25.5,...point(398,210)],[26.65,...point(315,71)],[28,...point(315,71)],[30.4,...point(200,379)],
    [33,...point(200,379)],[33.2,...point(650,400)],[34.6,...point(650,451)],[35,...point(260,414)],[36.2,...point(693,535)],[36.4,...point(693,535)],
    [37.6,...point(715,110)],[38.5,...point(77,127)],[38.8,...point(77,127)],[40.1,...point(133,133)],[40.5,...point(704,298)],[41,...point(704,298)],
    [41.85,...P.settings],[42.1,...P.settings],[43.3,...point(128,240)],[45.6,...point(690,479)],[47.2,...point(350,240)],[49.4,...P.back],
    [49.8,...P.back],[50.3,...P.weekly],[50.7,...P.weekly],[51.2,...P.export],[51.45,...P.export],[52.2,...point(390,177)],
    [53,...point(390,219)],[53.8,...point(390,279)],[54.6,...point(390,320)],[55.4,...P.daily],[55.6,...P.daily],[57,1530,956],[END,1530,956]
  ];
  p.compose(frame({x:0,y:0,width:30,height:42,layout:'none',animate:[anim('offsetX',moves.map(([t,x])=>[t,x])),anim('offsetY',moves.map(([t,x,y])=>[t,y]))]},[
    path({d:'M 2 1 L 3 32 L 11 24 L 18 40 L 24 37 L 17 22 L 29 21 Z',width:30,height:42,fill:'#FFFFFF',stroke:{width:2,color:'#3C2B4D'},shadow:{x:1,y:2,blur:4,color:'#00000055'}})
  ]),{at:0,dur:END,name:'Guided cursor'});
  const clicks=[[4.3,1690,390],[10.1,1685,900],[10.3,1685,900],[15.5,...P.files],[17.7,...P.all],[18.8,...P.weekly],[24.1,...P.search],[25.5,...point(398,210)],
    [26.65,...point(315,71)],[33,...point(200,379)],[36.4,...point(693,535)],[38.8,...point(77,127)],[40.1,...point(133,133)],[41,...point(704,298)],
    [42.1,...P.settings],[49.8,...P.back],[50.7,...P.weekly],[51.45,...P.export],[55.6,...P.daily]];
  for(let i=0;i<clicks.length;i++){
    const [at,x,y]=clicks[i];
    p.compose(rect({x:x-22,y:y-22,width:44,height:44,radius:22,fill:'#B086CC26',strokeColor:C.purple,strokeWidth:3,animate:[anim('scale',[[0,0.35],[0.45,1.5]]),anim('opacity',[[0,0.8],[0.45,0]])]}),{at,dur:0.45,name:`Click ${i+1}`});
  }
  if(Math.abs(p.duration()-END)>0.01) throw new Error(`Unexpected duration ${p.duration()}`);
};
