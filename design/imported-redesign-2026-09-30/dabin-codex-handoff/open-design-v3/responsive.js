/* Geometry helpers are shared by dragging, resizing and anchored project UI. */
function viewportRect(){const v=window.visualViewport;return {left:v?.offsetLeft||0,top:v?.offsetTop||0,width:v?.width||window.innerWidth,height:v?.height||window.innerHeight}}
function fitWindowRect(rect,viewport){
 const width=Math.min(Math.max(1,rect.width),viewport.width),height=Math.min(Math.max(1,rect.height),viewport.height);
 return {width,height,left:Math.max(viewport.left,Math.min(rect.left,viewport.left+viewport.width-width)),top:Math.max(viewport.top,Math.min(rect.top,viewport.top+viewport.height-height))};
}
function projectPanelRect(anchor,size,viewport){
 const gap=12,width=Math.min(size.width,viewport.width-gap*2),height=Math.min(size.height,viewport.height-gap*2);
 const bottom=viewport.top+viewport.height-gap,above=anchor.top-height-8;
 const top=anchor.bottom+8+height<=bottom?anchor.bottom+8:above>=viewport.top+gap?above:bottom-height;
 return {width,height,left:Math.max(viewport.left+gap,Math.min(anchor.left,viewport.left+viewport.width-width-gap)),top:Math.max(viewport.top+gap,top)};
}
function setFrameRect(frame,rect){Object.assign(frame.style,{position:'fixed',margin:'0',left:rect.left+'px',top:rect.top+'px',width:rect.width+'px',height:rect.height+'px'})}
function keepFrameInViewport(){
 const frame=$('#frame');if(!frame||!frame.getAttribute('style'))return;
 setFrameRect(frame,fitWindowRect(frame.getBoundingClientRect(),viewportRect()));
}

let frameRestoreStyle=null;
function toggleFrameExpansion(){const frame=$('#frame');if(!frame)return;
 if(frame.classList.contains('expanded')){frame.classList.remove('expanded');if(frameRestoreStyle)frame.setAttribute('style',frameRestoreStyle);else frame.removeAttribute('style');keepFrameInViewport()}
 else{frameRestoreStyle=frame.getAttribute('style');frame.removeAttribute('style');frame.classList.add('expanded')}
 positionProjectSwitcher();
}
