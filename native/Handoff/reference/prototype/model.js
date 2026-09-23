/* Pure capture model. Capture day/time never change when metadata is edited. */
(function(root){
  const dayKey=date=>`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
  const shift=(day,amount)=>{const d=new Date(day+'T12:00:00');d.setDate(d.getDate()+amount);return dayKey(d)};
  const group=entry=>entry.kind==='link'?'links':['image','video'].includes(entry.kind)?'media':['pdf','document','ai','file'].includes(entry.kind)?'files':'other';
  const normalize=text=>String(text||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase();
  const ordered=list=>[...list].sort((a,b)=>a.capturedAt.localeCompare(b.capturedAt)||a.id.localeCompare(b.id));
  const search=(entries,query,filter='all')=>{
    const words=normalize(query).trim().split(/\s+/).filter(Boolean);if(!words.length)return [];
    return [...new Set(entries.map(e=>e.day))].sort().reverse().flatMap(day=>{
      const list=ordered(entries.filter(e=>e.day===day));const hits=new Set();
      list.forEach((e,i)=>{const hay=normalize([e.title,e.description,e.original,e.comment,e.kind,e.day].join(' '));if((filter==='all'||group(e)===filter)&&words.every(w=>hay.includes(w)))hits.add(i)});
      if(!hits.size)return [];const included=new Set();hits.forEach(i=>[i-1,i,i+1].forEach(n=>{if(n>=0&&n<list.length)included.add(n)}));
      return [{day,hits:hits.size,items:[...included].sort((a,b)=>a-b).map(i=>({entry:list[i],match:hits.has(i)}))}];
    });
  };
  const fileKind=file=>{const ext=file.name.split('.').pop().toLowerCase();if(file.type.startsWith('image/')||['png','jpg','jpeg','gif','webp','svg','heic','avif'].includes(ext))return'image';if(file.type.startsWith('video/')||['mov','mp4','webm','m4v'].includes(ext))return'video';if(ext==='pdf')return'pdf';if(ext==='ai')return'ai';if(['doc','docx','ppt','pptx','xls','xlsx','txt','md','rtf','csv'].includes(ext))return'document';return'file'};
  const classify=text=>{try{const u=new URL(text.trim());return /^https?:$/.test(u.protocol)?'link':'text'}catch{return'text'}};
  const edit=(entry,comment,reminder)=>({...entry,comment,reminder,updatedAt:new Date().toISOString()});
  const seed=today=>{
    const base=(id,day,time,extra)=>({id,day,capturedAt:new Date(`${day}T${time}:00`).toISOString(),zone:Intl.DateTimeFormat().resolvedOptions().timeZone,comment:'',reminder:'',...extra});
    return [
      base('quiet-forms',today,'09:12',{kind:'image',title:'Quiet forms — a visual study',description:'Composition study · SVG',preview:'assets/quiet-forms.svg',original:'assets/quiet-forms.svg',source:'Image',sample:true}),
      base('thought',today,'09:36',{kind:'text',title:'Leave a little room for the unexpected.',description:'A note from this morning’s studio walk. Keep the quiet moments in the next concept.',original:'Leave a little room for the unexpected.\n\nA note from this morning’s studio walk. Keep the quiet moments in the next concept.',source:'Text',comment:'Use this as the opening thought.',sample:true}),
      base('studio-pdf',today,'10:04',{kind:'pdf',title:'Studio notes.pdf',description:'Materials, light and a quieter workspace.',preview:'assets/studio-notes.svg',original:'',source:'PDF',sample:true}),
      base('link-fallback',today,'10:27',{kind:'link',title:'fieldnotes.example / issue 08',description:'Preview unavailable. The original link is saved.',original:'https://fieldnotes.example/issue-08',source:'fieldnotes.example',sample:true}),
      base('video-fallback',today,'11:18',{kind:'video',title:'Afternoon light.mov',description:'Video · Preview unavailable',original:'',source:'Video',sample:true}),
      base('shapes-ai',today,'11:45',{kind:'ai',title:'Objects and shapes.ai',description:'Illustrator file · Preview unavailable',original:'',source:'Illustrator',sample:true}),
      base('yesterday-note',shift(today,-1),'14:10',{kind:'text',title:'Keep the room open, and the objects useful.',description:'A thought about how the studio should feel.',original:'Keep the room open, and the objects useful.',source:'Text',sample:true}),
      base('room-link',shift(today,-1),'14:25',{kind:'link',title:'A room for thinking',description:'Small spaces, thoughtful objects, and room to make things.',original:'https://stillroom.example/room-for-thinking',source:'stillroom.example',preview:'assets/quiet-forms.svg',sample:true,reminder:shift(today,1)+'T09:30'}),
      base('material-file',shift(today,-1),'14:42',{kind:'document',title:'Material shortlist.txt',description:'Brushed aluminium, recycled felt, frosted glass.',original:'assets/material-shortlist.txt',source:'Text document',sample:true}),
      base('earlier-link',shift(today,-2),'10:08',{kind:'link',title:'The everyday library',description:'Objects that earn a place in a room.',original:'https://commonplace.example/library',source:'commonplace.example',sample:true}),
      base('earlier-note',shift(today,-2),'10:32',{kind:'text',title:'Studio visit: look at the light first.',description:'Bring the materials and a notebook.',original:'Studio visit: look at the light first. Bring the materials and a notebook.',source:'Text',sample:true})
    ];
  };
  const api={dayKey,shift,group,normalize,ordered,search,fileKind,classify,edit,seed};root.DaBinModel=api;if(typeof module!=='undefined')module.exports=api;
})(typeof window==='undefined'?globalThis:window);
