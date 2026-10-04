"""Local Blender guided UI walkthrough with voice-synced native robot.

blender -b --python build_ui_tour.py -- --layout landscape --render
Use --frames 1,200,500 to inspect source resolution frames before full render.
"""
import bpy, math, json, argparse, sys, wave
from pathlib import Path

HERE=Path(__file__).resolve().parent;KIT=HERE.parents[1]
ASSETS=HERE.parent/'assets'; TEX=HERE/'textures'
edit=json.loads((HERE/'tour_edit.json').read_text())
ap=argparse.ArgumentParser();ap.add_argument('--layout',choices=['landscape','portrait'],default='landscape');ap.add_argument('--render',action='store_true');ap.add_argument('--frames');ap.add_argument('--ranges',help='Comma-separated inclusive frame intervals, e.g.325:355,482:589');args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
portrait=args.layout=='portrait';W,H=(1080,1920) if portrait else (1920,1080);FPS=30;P=100;END=edit['duration_seconds']
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.render.engine='BLENDER_EEVEE';s.render.resolution_x=W;s.render.resolution_y=H;s.render.resolution_percentage=100;s.render.fps=FPS;s.frame_start=1;s.frame_end=round(END*FPS)
s.eevee.taa_render_samples=8;s.eevee.use_shadows=False;s.view_settings.view_transform='Standard';s.view_settings.look='None'
s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGB';s.render.image_settings.compression=12
camera_data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',camera_data);s.collection.objects.link(camera);camera.location=(0,0,50);camera_data.type='ORTHO';camera_data.sensor_fit='HORIZONTAL';camera_data.ortho_scale=W/P;s.camera=camera
def frame(t):return max(1,round(t*FPS)+1)
def pos(x,y,z):return((x-W/2)/P,(H/2-y)/P,z)
def material(path):
    img=bpy.data.images.load(str(path),check_existing=True);m=bpy.data.materials.new(path.stem);m.use_nodes=True;m.surface_render_method='BLENDED'
    n=m.node_tree.nodes;n.clear();o=n.new('ShaderNodeOutputMaterial');mix=n.new('ShaderNodeMixShader');tr=n.new('ShaderNodeBsdfTransparent');em=n.new('ShaderNodeEmission');tex=n.new('ShaderNodeTexImage');tex.image=img;tex.extension='CLIP';uv=n.new('ShaderNodeTexCoord');scale=n.new('ShaderNodeVectorMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=(1,1,1);offset=n.new('ShaderNodeVectorMath');offset.operation='ADD'
    alpha=n.new('ShaderNodeMath');alpha.operation='MULTIPLY';alpha.inputs[1].default_value=1
    links=m.node_tree.links;links.new(uv.outputs['UV'],scale.inputs[0]);links.new(scale.outputs[0],offset.inputs[0]);links.new(offset.outputs[0],tex.inputs[0]);links.new(tex.outputs['Color'],em.inputs['Color']);links.new(tex.outputs['Alpha'],alpha.inputs[0]);links.new(alpha.outputs[0],mix.inputs[0]);links.new(tr.outputs[0],mix.inputs[1]);links.new(em.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],o.inputs[0])
    return img,m,alpha,scale,offset
def plane(name,path,x,y,width,height=None,z=2):
    img,m,alpha,scale,offset=material(path);height=height or width*img.size[1]/img.size[0]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([(-width/2/P,-height/2/P,0),(width/2/P,-height/2/P,0),(width/2/P,height/2/P,0),(-width/2/P,height/2/P,0)],[],[(0,1,2,3)]);mesh.uv_layers.new(name='UVMap')
    for li,uv in zip(mesh.polygons[0].loop_indices,[(0,0),(1,0),(1,1),(0,1)]):mesh.uv_layers.active.data[li].uv=uv
    obj=bpy.data.objects.new(name,mesh);s.collection.objects.link(obj);obj.data.materials.append(m);obj.location=pos(x,y,z);obj['source_asset']=path.name
    return {'o':obj,'a':alpha,'scale':scale,'offset':offset,'size':list(img.size),'width':width,'height':height}
def alpha(q,t,value):q['a'].inputs[1].default_value=value;q['a'].inputs[1].keyframe_insert('default_value',frame=frame(t))
def visible(q,start,end,fade=.12):
    alpha(q,0,0);alpha(q,max(0,start-.001),0);alpha(q,start+fade,1);alpha(q,max(start+fade,end-fade),1);alpha(q,end,0)
def move(q,t,x,y,angle=None,scale=None):
    q['o'].location=pos(x,y,q['o'].location.z);q['o'].keyframe_insert('location',frame=frame(t))
    if angle is not None:q['o'].rotation_euler.z=math.radians(-angle);q['o'].keyframe_insert('rotation_euler',frame=frame(t))
    if scale is not None:q['o'].scale=(scale,scale,1);q['o'].keyframe_insert('scale',frame=frame(t))
def crop(q,t,r):
    iw,ih=q['size'];x,y,w,h=r
    q['scale'].inputs[1].default_value=(w/iw,h/ih,1);q['scale'].inputs[1].keyframe_insert('default_value',frame=frame(t))
    q['offset'].inputs[1].default_value=(x/iw,1-(y+h)/ih,0);q['offset'].inputs[1].keyframe_insert('default_value',frame=frame(t))
def fit_crop(iw,ih,cx,cy,width,aspect):
    width=min(width,iw,ih*aspect);h=width/aspect
    return [max(0,min(iw-width,cx-width/2)),max(0,min(ih-h,cy-h/2)),width,h]
L='PORTRAIT' if portrait else 'LANDSCAPE'
plane('Background',TEX/f'DABIN__TOUR__BACKDROP_{L}.png',W/2,H/2,W,z=0)
uiX,uiY,uiW,uiH=(40,245,1000,1000) if portrait else (30,143,1500,1500*1404/2360)
cx,cy=uiX+uiW/2,uiY+uiH/2
cursor=plane('Demonstration cursor',TEX/'DABIN__TOUR__CURSOR.png',0,0,42,z=20);alpha(cursor,0,0)
ring=plane('Click emphasis',TEX/'DABIN__TOUR__CLICK_RING.png',0,0,76,z=19);alpha(ring,0,0)
for shot in edit['shots']:
    start,end=shot['start'],shot['end'];q=plane('Native '+shot['asset']+' '+str(start),ASSETS/shot['asset'],cx,cy,uiW,uiH,z=3);visible(q,start,end)
    iw,ih=q['size'];aspect=uiW/uiH
    focus=shot.get('focus',[iw/2,ih/2,iw]);pcrop=shot.get('portrait_focus',focus)
    chosen=pcrop if portrait else focus
    r=fit_crop(iw,ih,*chosen,aspect)
    # Landscape begins wide, moves to the actual control, then holds so it can be read.
    # Portrait uses a larger native detail crop throughout for phone legibility.
    first=r if portrait else fit_crop(iw,ih,iw/2,ih/2,iw,aspect)
    crop(q,start,first);crop(q,start+.35,first);crop(q,min(end-.35,start+1.15),r);crop(q,end,r)
    p=shot.get('pointer')
    if p:
        px=uiX+(p[0]-r[0])/r[2]*uiW;py=uiY+(p[1]-r[1])/r[3]*uiH
        if uiX+10<px<uiX+uiW-10 and uiY+10<py<uiY+uiH-10:
            at=min(end-.6,start+1.5)
            move(cursor,at-.5,px+70,py+90);move(cursor,at,px,py);move(cursor,at+.26,px,py)
            visible(cursor,at-.55,min(end-.05,at+.65),.08)
            move(ring,at,px+3,py+3,scale=.6);move(ring,at+.32,px+3,py+3,scale=1.3);visible(ring,at,at+.36,.08)
for ch in edit['chapters']:
    start,end=ch['start'],ch['end'];ci=ch['id']
    q=plane('Chapter '+str(ci),TEX/f'DABIN__TOUR__TITLE_{L}_{ci:02}.png',540 if portrait else 790,177 if portrait else 105,990 if portrait else 1520,z=10);visible(q,start,end)
    q=plane('Robot guide '+str(ci),TEX/f'DABIN__TOUR__BUBBLE_{L}_{ci:02}.png',695 if portrait else 1750,1545 if portrait else 390,650 if portrait else 270,z=10);visible(q,start,end,.16)
    if ci==13:
        # The backup instruction has its own beat before the rescue explanation.
        end_backup=edit['narration_offset_seconds']+70.62+sum(p['seconds'] for p in edit['reading_pauses'] if 70.62>=p['source_at'])
        alpha(q,start+.16,0);alpha(q,end_backup-.01,0);alpha(q,end_backup+.12,1)
        b=plane('Robot explains backup route',TEX/f'DABIN__TOUR__BUBBLE_{L}_BACKUP.png',695 if portrait else 1750,1545 if portrait else 390,650 if portrait else 270,z=10)
        visible(b,start,end_backup,.12)
# The robot stays at the interface, listens during pauses and reacts to actions.
rx,ry,rw=(201,1575,290) if portrait else (1750,741,260)
robot=plane('Native robot guide',ASSETS/'DABIN__ROBOT__IDLE.png',rx,ry,rw,z=12)
for ci,ch in enumerate(edit['chapters']):
    move(robot,ch['start'],rx,ry,angle=0)
    move(robot,ch['start']+.8,rx-5,ry-3,angle=-2 if ci%3 else 2)
    move(robot,min(ch['end']-.2,ch['start']+2.3),rx,ry,angle=0)
def source_time(sec):return sec+edit['narration_offset_seconds']+sum(p['seconds'] for p in edit['reading_pauses'] if sec>=p['source_at'])
# A single illustrative drag uses the same fictional image as the real saved
# native endpoint. It happens on the Inbox, rather than flying across an ad.
drag=plane('Fictional palette dragged to Inbox',ASSETS/'DABIN__SAMPLE__STUDIO_REFERENCE.png',220 if not portrait else 220,790 if not portrait else 880,330 if not portrait else 400,z=17)
visible(drag,source_time(1.88),source_time(4.6),.18)
for st,x,y in [(1.88,220,790),(2.6,330,690),(3.65,660,555),(4.3,780,545)]:
    move(drag,source_time(st),x if not portrait else x*.8+70,y if not portrait else y+200)
# The next native image state is the actual saved result, using the same pixels.
for mood,start,end in [('CURIOUS_LEFT',source_time(18.38),source_time(24.76)),('PUZZLED',source_time(32.3),source_time(35)),('CURIOUS_LEFT',source_time(35),source_time(43.62)),('DELIGHTED',source_time(73.4),END)]:
    path=ASSETS/f'DABIN__ROBOT__{mood}.png'
    if path.exists():
        pose=plane('Native '+mood+' '+str(start),path,rx,ry,rw,z=12.5)
        pose['o'].parent=robot['o'];pose['o'].location=(0,0,.5);visible(pose,start,end,.10)
# Actual native focus alarm is an explicitly labeled timer-end example.
alarm=plane('Native focus alarm example',ASSETS/'DABIN__ROBOT__FOCUS_ALARM.png',950 if not portrait else 540,880 if not portrait else 1100,480 if not portrait else 600,z=11)
visible(alarm,source_time(54.28),source_time(56.62),.16)
example=plane('Timer end example label',TEX/'DABIN__TOUR__TIMER_EXAMPLE.png',950 if not portrait else 540,1010 if not portrait else 1290,430 if not portrait else 590,z=11)
visible(example,source_time(54.28),source_time(56.62),.16)
# Mouth patch uses native open-mouth pixels, keyed to actual speech energy.
mouth=plane('Native voice-synced mouth',ASSETS/'DABIN__MOUTH__HUNGRY.png',rx,ry,rw,z=13)
alpha(mouth,0,0)
with wave.open(str(KIT/'04_Video/audio/DABIN__UI_TOUR__MIX.wav')) as w:
    import struct
    rate=w.getframerate();channels=w.getnchannels();samples=struct.unpack('<'+'h'*(w.getnframes()*channels),w.readframes(w.getnframes()))
for fr in range(1,s.frame_end+1,2):
    t=(fr-1)/FPS; a=int(t*rate)*channels;b=min(len(samples),a+int(rate*.067)*channels);seg=samples[a:b]
    rms=math.sqrt(sum(v*v for v in seg)/max(1,len(seg))) if seg else 0
    mouth['a'].inputs[1].default_value=1 if rms>550 and math.sin(t*31+math.sin(t*4))>-.05 else 0
    mouth['a'].inputs[1].keyframe_insert('default_value',frame=fr)
# Mouth follows small nods via constraint without affecting source geometry.
# Convert guide coordinates into local coordinates and parent it to the robot.
mouth['o'].parent=robot['o'];mouth['o'].location=(0,0,1)
if (ASSETS/'DABIN__ROBOT__BLINK.png').exists():
    blink=plane('Native blink',ASSETS/'DABIN__ROBOT__BLINK.png',rx,ry,rw,z=14)
    blink['o'].parent=robot['o'];blink['o'].location=(0,0,2);alpha(blink,0,0)
    for bt in [4.9,11.2,18.4,27.6,35.1,44.7,53.3,63.6,72.1,81.4,89.7]:
        if bt<END:
            visible(blink,bt,bt+.15,.035)
progress=plane('Tour progress',TEX/'DABIN__TOUR__PROGRESS.png',W/2,H-12,W-80,6,z=15)
progress['o'].scale.x=.001;progress['o'].keyframe_insert('scale',frame=1);progress['o'].scale.x=1;progress['o'].keyframe_insert('scale',frame=s.frame_end)
for action in bpy.data.actions:
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for kp in fc.keyframe_points:kp.interpolation='LINEAR'
# A closed smile and an open vowel never dissolve into a double mouth.
ma=mouth['a'].id_data.animation_data.action
for layer in ma.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for kp in fc.keyframe_points:kp.interpolation='CONSTANT'
s['title']='DaBin explains the UI';s['ui_version']='0.4.31 (86)';s['editorial_disclosure']='Actual native offscreen views with fictional data. Composed guide, cursor and transitions; not continuous live screen recording.';s['duration_seconds']=END;s['speech']='Natural-speed ElevenLabs Andre Rene'
s.frame_set(1);bpy.ops.file.pack_all();blend=HERE/f'DABIN__UI_TOUR__{args.layout.upper()}.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend))
out=KIT/'.work'/f'frames_{args.layout}';out.mkdir(parents=True,exist_ok=True)
if args.frames:
    for fr in map(int,args.frames.split(',')):
        s.frame_set(fr);s.render.filepath=str(out/f'DABIN__FRAME__{fr:04}.png');bpy.ops.render.render(write_still=True)
elif args.ranges:
    for interval in args.ranges.split(','):
        begin,end=map(int,interval.split(':'));s.frame_start=begin;s.frame_end=end
        s.render.filepath=str(out/'DABIN__FRAME__');bpy.ops.render.render(animation=True)
elif args.render:
    s.render.filepath=str(out/'DABIN__FRAME__');bpy.ops.render.render(animation=True)
print(json.dumps({'blend':str(blend),'frames':s.frame_end,'duration_seconds':END,'layout':args.layout}))
