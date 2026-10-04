// Local layout review for authored HTML only. No user browser session is used.
const fs=require('fs'),path=require('path'),http=require('http');
const {chromium}=require(process.env.DABIN_PLAYWRIGHT || 'playwright');
const kit=path.resolve(__dirname,'../..');
const qa=path.join(kit,'07_QA');
const types={'.html':'text/html','.js':'text/javascript','.png':'image/png','.mp4':'video/mp4','.vtt':'text/vtt','.txt':'text/plain'};
const server=http.createServer((req,res)=>{
 const f=path.resolve(kit,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
 if(!f.startsWith(kit+path.sep) || !fs.existsSync(f) || fs.statSync(f).isDirectory()){res.writeHead(404);res.end();return;}
 res.setHeader('Content-Type',types[path.extname(f)]||'application/octet-stream');
 fs.createReadStream(f).pipe(res);
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base='http://127.0.0.1:'+server.address().port;
 const b=await chromium.launch({headless:true});const results=[];
 for(const [name,url,width,height] of [['LANDING_DESKTOP','05_Landing_Page/index.html',1440,1100],['LANDING_MOBILE','05_Landing_Page/index.html',390,844],['KIT_INDEX','START_HERE.html',1440,1100]]){
   const page=await b.newPage({viewport:{width,height},deviceScaleFactor:1});
   await page.route('**/*',route=>route.request().url().startsWith(base)?route.continue():route.abort());
   const errors=[];page.on('pageerror',e=>errors.push(String(e)));
   await page.goto(base+'/'+url,{waitUntil:'networkidle'});
   const facts=await page.evaluate(()=>({width:innerWidth,contentWidth:document.documentElement.scrollWidth,images:[...document.images].map(i=>({src:i.getAttribute('src'),loaded:i.complete&&i.naturalWidth>0,naturalWidth:i.naturalWidth,naturalHeight:i.naturalHeight,renderWidth:i.getBoundingClientRect().width,renderHeight:i.getBoundingClientRect().height})),video:[...document.querySelectorAll('video')].map(v=>({readyState:v.readyState,duration:v.duration,videoWidth:v.videoWidth,videoHeight:v.videoHeight})),downloads:[...document.querySelectorAll('.download')].map(a=>({disabled:a.getAttribute('aria-disabled'),href:a.getAttribute('href')}))}));
   if(facts.contentWidth>facts.width || facts.images.some(i=>!i.loaded || Math.abs((i.renderWidth/i.renderHeight)/(i.naturalWidth/i.naturalHeight)-1)>.01) || errors.length)throw new Error(name+' layout/load/aspect errors '+JSON.stringify({facts,errors}));
   await page.screenshot({path:path.join(qa,'DABIN__QA__'+name+'.png'),fullPage:true});
   results.push({name,facts,errors});await page.close();
 }
 await b.close();server.close();
 fs.writeFileSync(path.join(qa,'html-layout-verification.json'),JSON.stringify({local_only:true,results},null,2));
 console.log('PASS: desktop/mobile landing and kit index render, assets load, no horizontal overflow or JS exceptions.');
})().catch(e=>{console.error(e);server.close();process.exitCode=1});
