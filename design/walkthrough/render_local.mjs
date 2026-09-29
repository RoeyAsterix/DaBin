#!/usr/bin/env node
// Independently implemented local composition adapter. Uses the authored source,
// public @napi-rs/canvas and public FFmpeg; no hosted service or private runtime.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawn, execFileSync} from 'node:child_process';
import {once} from 'node:events';

const HERE=path.dirname(fileURLToPath(import.meta.url));
const ROOT=path.resolve(HERE,'../..');
const require=createRequire(import.meta.url);
let canvasModule;
try { canvasModule=require('@napi-rs/canvas'); }
catch {
  const modulePath=process.env.DABIN_CANVAS_MODULE || path.join(path.dirname(process.execPath),'../node_modules/@napi-rs/canvas');
  canvasModule=require(modulePath);
}
const {createCanvas,loadImage,Path2D,GlobalFonts}=canvasModule;
// App typography is rasterized by the production renderer. Only the editorial
// guide uses this installed system face when DM Sans is not installed.
for(const [file,family] of [['Arial.ttf','Arial'],['Arial Bold.ttf','Arial']]){
  const font=path.join('/System/Library/Fonts/Supplemental',file);
  if(fs.existsSync(font)) GlobalFonts.registerFromPath(font,family);
}

const argv=process.argv.slice(2);
const mode=argv.shift() || 'check';
const options={};
while(argv.length){
  const flag=argv.shift();
  if(!flag.startsWith('--')) throw new Error(`Expected an option, received ${flag}`);
  const value=argv.shift();
  if(value===undefined || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
  options[flag.slice(2)]=value;
}
if(!['build','check','sheet','render'].includes(mode)) throw new Error('Modes: build, check, sheet, render');
const source=path.resolve(options.source||path.join(HERE,'build_walkthrough.js'));
process.env.DABIN_REPO_ROOT ||= ROOT;
const assets=new Map(),scenes=[],audio=[];
let settings;

function audioDuration(file){
  const info=execFileSync('/usr/bin/afinfo',[file],{encoding:'utf8'});
  const match=info.match(/estimated duration:\s*([\d.]+)/);
  if(!match || Number(match[1])<=0) throw new Error(`No usable audio: ${file}`);
  return Number(match[1]);
}
async function project(config){
  if(settings) throw new Error('Only one project per source is supported');
  const [width,height]=config.size.split('x').map(Number);
  settings={...config,width,height};
  return {
    async add(file){
      const absolute=path.resolve(file);
      if(assets.has(absolute)) return assets.get(absolute);
      if(!fs.existsSync(absolute)) throw new Error(`Missing authored asset: ${absolute}`);
      let asset;
      if(/\.(aiff?|wav|m4a|mp3)$/i.test(absolute)) asset={path:absolute,kind:'audio',duration:audioDuration(absolute)};
      else { const image=await loadImage(absolute); asset={path:absolute,kind:'image',image,width:image.width,height:image.height}; }
      assets.set(absolute,asset);return asset;
    },
    compose(nodes,timing){scenes.push({...timing,nodes:Array.isArray(nodes)?nodes:[nodes]});},
    cut(asset,timing){if(asset.kind!=='audio')throw new Error('cut currently supports narration audio only');audio.push({...timing,asset});},
    duration(){return Math.max(0,...scenes.map(s=>s.at+s.dur),...audio.map(a=>a.at+a.dur));}
  };
}
const constructors={
  project,
  frame:(props,children=[])=>({type:'frame',...props,children}),
  media:props=>({type:'media',...props}),
  rect:props=>({type:'rect',...props}),
  path:props=>({type:'path',...props}),
  text:(content,props)=>({type:'text',content,...props})
};
await (await import(pathToFileURL(source))).default(constructors);
if(!settings)throw new Error('Source did not create a project');
const duration=Math.max(...scenes.map(s=>s.at+s.dur),...audio.map(a=>a.at+a.dur));
const width=settings.width,height=settings.height,fps=settings.fps;
const defaultDir=path.resolve(settings.dir);
fs.mkdirSync(defaultDir,{recursive:true});

function animated(node,t){
  const values={...node};
  for(const track of node.animate||[]){
    const keys=track.keyframes;
    let value=keys[0].value;
    if(t>=keys.at(-1).at)value=keys.at(-1).value;
    else for(let i=0;i<keys.length-1;i++){
      const a=keys[i],b=keys[i+1];
      if(t>=a.at && t<b.at){
        let u=(t-a.at)/(b.at-a.at);
        if(b.easing!=='linear')u=u*u*(3-2*u);
        value=a.value+(b.value-a.value)*u;break;
      }
    }
    values[track.property]=value;
  }
  return values;
}
function fillStyle(ctx,fill,w,h){
  if(typeof fill!=='object')return fill||'transparent';
  if(fill.kind!=='linear')throw new Error(`Unsupported fill ${fill.kind}`);
  const angle=(fill.angle||0)*Math.PI/180;
  const dx=Math.cos(angle)*w/2,dy=Math.sin(angle)*h/2;
  const gradient=ctx.createLinearGradient(w/2-dx,h/2-dy,w/2+dx,h/2+dy);
  for(const stop of fill.stops)gradient.addColorStop(stop.offset,stop.color);
  return gradient;
}
function setShadow(ctx,shadow){
  ctx.shadowColor=shadow?.color||'transparent';ctx.shadowBlur=shadow?.blur||0;
  ctx.shadowOffsetX=shadow?.x||0;ctx.shadowOffsetY=shadow?.y||0;
}
function font(node){return `${node.fontWeight||400} ${node.fontSize||24}px Arial`;}
function lines(ctx,node){
  const output=[];
  for(const paragraph of node.content.split('\n')){
    let line='';
    for(const word of paragraph.split(/\s+/)){
      const candidate=line?`${line} ${word}`:word;
      if(line && ctx.measureText(candidate).width>node.width){output.push(line);line=word;}
      else line=candidate;
    }
    output.push(line);
  }
  return output;
}
function drawNode(ctx,original,t){
  const node=animated(original,t),w=node.width||0,h=node.height||0;
  ctx.save();
  ctx.translate((node.x||0)+(node.offsetX||0),(node.y||0)+(node.offsetY||0));
  const ox=node.origin==='center'?w/2:0,oy=node.origin==='center'?h/2:0;
  ctx.translate(ox,oy);ctx.rotate((node.rotation||0)*Math.PI/180);
  ctx.scale((node.scale??1)*(node.scaleX??1),(node.scale??1)*(node.scaleY??1));ctx.translate(-ox,-oy);
  ctx.globalAlpha*=node.opacity??1;
  setShadow(ctx,node.shadow);
  if(node.type==='frame'){
    if(node.clip){ctx.beginPath();ctx.rect(0,0,w,h);ctx.clip();}
    for(const child of node.children)drawNode(ctx,child,t);
  } else if(node.type==='media'){
    const image=node.file.image;
    const scale=node.fit==='cover'?Math.max(w/image.width,h/image.height):Math.min(w/image.width,h/image.height);
    const dw=image.width*scale,dh=image.height*scale;
    ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';
    ctx.drawImage(image,(w-dw)/2,(h-dh)/2,dw,dh);
  } else if(node.type==='rect'){
    ctx.beginPath();ctx.roundRect(0,0,w,h,node.radius||0);
    ctx.fillStyle=fillStyle(ctx,node.fill,w,h);ctx.fill();
    if(node.strokeWidth){setShadow(ctx,null);ctx.lineWidth=node.strokeWidth;ctx.strokeStyle=node.strokeColor;ctx.stroke();}
  } else if(node.type==='path'){
    const shape=new Path2D(node.d);ctx.fillStyle=fillStyle(ctx,node.fill,w,h);ctx.fill(shape);
    if(node.stroke){setShadow(ctx,null);ctx.lineWidth=node.stroke.width;ctx.strokeStyle=node.stroke.color;ctx.stroke(shape);}
  } else if(node.type==='text'){
    ctx.font=font(node);ctx.fillStyle=node.color||'#000';ctx.textBaseline='top';ctx.textAlign=node.align||'left';
    if(node.letterSpacing)ctx.letterSpacing=`${node.letterSpacing}px`;
    const x=node.align==='center'?w/2:node.align==='right'?w:0;
    const lineHeight=(node.lineHeight||1.2)*(node.fontSize||24);
    lines(ctx,node).forEach((line,index)=>ctx.fillText(line,x,index*lineHeight));
  } else throw new Error(`Unknown node ${node.type}`);
  ctx.restore();
}
const canvas=createCanvas(width,height),ctx=canvas.getContext('2d');
function draw(t){
  ctx.resetTransform();ctx.globalAlpha=1;setShadow(ctx,null);
  ctx.fillStyle=settings.background||'#000';ctx.fillRect(0,0,width,height);
  for(const scene of scenes)if(t>=scene.at && t<scene.at+scene.dur)for(const node of scene.nodes)drawNode(ctx,node,t-scene.at);
  return canvas;
}
const problems=[];
function checkNode(node,scene){
  if(!node.type || !Number.isFinite(node.width)||!Number.isFinite(node.height)||node.width<=0||node.height<=0)problems.push(`${scene}: invalid node size`);
  if(node.type==='media' && node.file.kind!=='image')problems.push(`${scene}: missing image`);
  if(node.type==='text'){
    ctx.font=font(node);const count=lines(ctx,node).length;
    if(count*(node.fontSize||24)*(node.lineHeight||1.2)>node.height+1)problems.push(`${scene}: text exceeds height: ${node.content}`);
  }
  for(const track of node.animate||[]){
    if(!['offsetX','offsetY','rotation','scale','scaleX','scaleY','opacity'].includes(track.property))problems.push(`${scene}: unsupported animation ${track.property}`);
    track.keyframes.forEach((key,i)=>{if(!Number.isFinite(key.at)||!Number.isFinite(key.value)||(i&&key.at<track.keyframes[i-1].at))problems.push(`${scene}: invalid animation keyframe`);});
  }
  (node.children||[]).forEach(child=>checkNode(child,scene));
}
for(const scene of scenes){
  if(!Number.isFinite(scene.at)||!Number.isFinite(scene.dur)||scene.at<0||scene.dur<=0)problems.push(`Invalid scene: ${scene.name}`);
  scene.nodes.forEach(node=>checkNode(node,scene.name));
}
if(width!==1920||height!==1080||fps!==30||duration<55||duration>65)problems.push('Walkthrough must be 1920×1080, 30 fps, 55–65 seconds');
for(const clip of audio)if(clip.dur<=0||clip.from<0||clip.from+clip.dur>clip.asset.duration+0.01)problems.push('Invalid audio trim');
const summary={adapter:'DaBin local canvas / public FFmpeg',source,width,height,fps,durationSeconds:duration,
  frames:Math.ceil(duration*fps),visualScenes:scenes.length,audioClips:audio.length,assets:assets.size,
  guideFont:'Arial (installed system font; production UI typography is preserved in exact native rasters)',
  errors:problems,scenes:scenes.map(({name,at,dur})=>({name,at,dur})),audio:audio.map(({asset,...clip})=>({...clip,file:asset.path}))};
fs.writeFileSync(path.join(defaultDir,'local-composition.json'),JSON.stringify(summary,null,2)+'\n');
if(problems.length)throw new Error(`Composition check failed:\n${problems.join('\n')}`);
console.log(`CHECK PASS: ${width}×${height}, ${fps} fps, ${duration}s, ${scenes.length} visual layers, ${audio.length} narration clips`);

if(mode==='sheet'){
  const times=(options.times||'1,5.5,8,12,16,21,29,35.8,39.3,41.4,44,48,53,57').split(',').map(Number);
  if(times.some(t=>!Number.isFinite(t)||t<0||t>=duration))throw new Error('Invalid contact-sheet time');
  const columns=Number(options.cols||3),cellW=640,cellH=360,pad=20,label=34;
  const sheet=createCanvas(columns*cellW+(columns+1)*pad,Math.ceil(times.length/columns)*(cellH+label+pad)+pad);
  const sc=sheet.getContext('2d');sc.fillStyle='#17131C';sc.fillRect(0,0,sheet.width,sheet.height);
  for(let index=0;index<times.length;index++){
    const x=pad+(index%columns)*(cellW+pad),y=pad+Math.floor(index/columns)*(cellH+label+pad);
    sc.drawImage(draw(times[index]),x,y,cellW,cellH);sc.font='20px Arial';sc.fillStyle='#F0E9F4';sc.fillText(`${times[index].toFixed(2)} s`,x,y+cellH+25);
  }
  const out=path.resolve(options.out||path.join(defaultDir,'contact-sheet.png'));fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,await sheet.encode('png'));console.log(out);
} else if(mode==='render'){
  let ffmpeg=process.env.DABIN_FFMPEG;
  if(!ffmpeg){
    const bins=path.join(ROOT,'native/build/walkthrough-tools/imageio_ffmpeg/binaries');
    ffmpeg=fs.readdirSync(bins).filter(file=>file.startsWith('ffmpeg-')).map(file=>path.join(bins,file))[0];
  }
  if(!ffmpeg||!fs.existsSync(ffmpeg))throw new Error('Set DABIN_FFMPEG to a public FFmpeg executable');
  const out=path.resolve(options.out||path.join(ROOT,'output/video/DaBin-App-Walkthrough-59s.mp4'));
  fs.mkdirSync(path.dirname(out),{recursive:true});
  const temporary=out.replace(/\.mp4$/i,'')+'.rendering.mp4';
  const args=['-hide_banner','-y','-f','rawvideo','-pix_fmt','rgba','-s',`${width}x${height}`,'-r',String(fps),'-i','pipe:0'];
  for(const clip of audio)args.push('-i',clip.asset.path);
  if(audio.length){
    const filters=audio.map((clip,i)=>`[${i+1}:a]atrim=start=${clip.from}:duration=${clip.dur},asetpts=PTS-STARTPTS,aresample=48000,adelay=${Math.round(clip.at*1000)}:all=1[a${i}]`);
    filters.push(audio.map((_,i)=>`[a${i}]`).join('')+`amix=inputs=${audio.length}:normalize=0:duration=longest,apad,atrim=duration=${duration}[mix]`);
    args.push('-filter_complex',filters.join(';'),'-map','0:v:0','-map','[mix]','-c:a','aac','-b:a','160k','-ar','48000','-ac','2');
  }
  args.push('-c:v','libx264','-preset',options.preset||'medium','-crf',options.crf||'18','-pix_fmt','yuv420p','-r',String(fps),'-t',String(duration),'-movflags','+faststart',temporary);
  fs.writeFileSync(path.join(defaultDir,'local-render-command.json'),JSON.stringify({executable:ffmpeg,args},null,2)+'\n');
  const encoder=spawn(ffmpeg,args,{stdio:['pipe','ignore','pipe']});let encoderLog='';
  encoder.stderr.on('data',chunk=>{encoderLog+=chunk.toString();if(encoderLog.length>100000)encoderLog=encoderLog.slice(-100000);});
  const completed=new Promise((resolve,reject)=>{encoder.once('error',reject);encoder.once('close',code=>code===0?resolve():reject(new Error(`FFmpeg exited ${code}\n${encoderLog}`)));});
  // Prevent an early encoder failure from becoming an unhandled rejection while
  // the frame producer finishes its current synchronous raster operation.
  completed.catch(()=>{});encoder.stdin.on('error',()=>{});
  try{
    for(let index=0;index<summary.frames;index++){
      draw(index/fps);const rgba=ctx.getImageData(0,0,width,height).data;
      if(!encoder.stdin.write(Buffer.from(rgba.buffer,rgba.byteOffset,rgba.byteLength)))await Promise.race([once(encoder.stdin,'drain'),completed.then(()=>{throw new Error('Encoder stopped before receiving all frames');})]);
      if(index%150===0)console.log(`RENDER ${index}/${summary.frames} (${(index/fps).toFixed(1)}s)`);
    }
    encoder.stdin.end();await completed;
  }catch(error){encoder.kill('SIGTERM');throw error;}
  fs.writeFileSync(path.join(defaultDir,'ffmpeg-render.log'),encoderLog);
  fs.renameSync(temporary,out);console.log(`RENDER COMPLETE: ${out}`);
}
