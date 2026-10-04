"""Blender 5.x 2D editorial animation from exact DaBin artwork and native UI.

blender -b --python build_feed_dabin.py -- --layout landscape --render
Also supports --layout portrait --render, --frames 60,190,290 and --draft.
Packed .blend files contain the editable animation and texture media.
"""
import bpy, math, json, argparse, sys
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent; KIT=HERE.parents[1]
TEX=HERE/'textures'; ASSETS=HERE.parent/'assets'
ap=argparse.ArgumentParser();ap.add_argument('--layout',choices=['landscape','portrait'],default='landscape')
ap.add_argument('--render',action='store_true');ap.add_argument('--frames');ap.add_argument('--draft',action='store_true')
args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
portrait=args.layout=='portrait'; W,H=(1080,1920) if portrait else (1920,1080)
FPS=30; END=22; P=100.0
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=W;scene.render.resolution_y=H;scene.render.resolution_percentage=50 if args.draft else 100
scene.render.fps=FPS;scene.frame_start=1;scene.frame_end=FPS*END
scene.eevee.taa_render_samples=8;scene.eevee.use_shadows=False
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB';scene.render.image_settings.compression=15
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.world.color=(1,1,1);scene.render.film_transparent=False
camera_data=bpy.data.cameras.new('Camera');camera=bpy.data.objects.new('Camera',camera_data)
scene.collection.objects.link(camera);camera.location=(0,0,50);camera_data.type='ORTHO';camera_data.sensor_fit='HORIZONTAL';camera_data.ortho_scale=W/P
scene.camera=camera
def pos(x,y,z):return((x-W/2)/P,(H/2-y)/P,z)
def texture(path):
    img=bpy.data.images.load(str(path),check_existing=True)
    m=bpy.data.materials.new(path.stem);m.use_nodes=True;m.surface_render_method='BLENDED'
    nodes=m.node_tree.nodes;nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial');mix=nodes.new('ShaderNodeMixShader')
    trans=nodes.new('ShaderNodeBsdfTransparent');em=nodes.new('ShaderNodeEmission');tex=nodes.new('ShaderNodeTexImage');tex.image=img
    m.node_tree.links.new(tex.outputs['Color'],em.inputs['Color']);em.inputs['Strength'].default_value=1
    m.node_tree.links.new(tex.outputs['Alpha'],mix.inputs[0]);m.node_tree.links.new(trans.outputs[0],mix.inputs[1]);m.node_tree.links.new(em.outputs[0],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],out.inputs[0])
    return img,m
def plane(name,path,x,y,width=None,height=None,z=1):
    img,mat=texture(path)
    if width is None:width=height*img.size[0]/img.size[1]
    if height is None:height=width*img.size[1]/img.size[0]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([(-width/2/P,-height/2/P,0),(width/2/P,-height/2/P,0),(width/2/P,height/2/P,0),(-width/2/P,height/2/P,0)],[],[(0,1,2,3)])
    mesh.uv_layers.new(name='UVMap')
    for li,uv in zip(mesh.polygons[0].loop_indices,[(0,0),(1,0),(1,1),(0,1)]):mesh.uv_layers.active.data[li].uv=uv
    o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o);o.data.materials.append(mat);o.location=pos(x,y,z)
    o['source_asset']=path.name;return o
def key(o,t,x=None,y=None,scale=1,z=None):
    if x is not None:o.location=pos(x,y,o.location.z if z is None else z);o.keyframe_insert('location',frame=max(1,int(t*FPS)+1))
    o.scale=(scale,scale,scale);o.keyframe_insert('scale',frame=max(1,int(t*FPS)+1))
def active(o,start,end,fly=True):
    key(o,0,scale=0);key(o,max(0,start-.025),scale=0)
    key(o,start+.18,scale=1);key(o,end-.12,scale=1);key(o,end,scale=0)
def txt(name,x,y,width=None,height=None,z=10):
    return plane(name,TEX/('DABIN__TEXT__'+name+'.png'),x,y,width,height,z)
def pill(name,x,y,width=None,z=15):return plane('Pill '+name,TEX/('DABIN__PILL__'+name+'.png'),x,y,width=width,z=z)
suffix='P' if portrait else 'L'
plane('Backdrop',TEX/('DABIN__BACKDROP__'+args.layout.upper()+'.png'),W/2,H/2,width=W,z=0)
brand=txt('BRAND',145 if portrait else 160,125 if portrait else 94,width=160)
txt('FOR_MAC',315 if portrait else 330,131 if portrait else 100,width=90)
txt('COMPAT_'+suffix,W/2 if portrait else 270,H-218 if portrait else H-55,width=820 if portrait else 390)

intro=txt('INTRO_'+suffix,540 if portrait else 525,355 if portrait else 382,width=970 if portrait else 900)
sub=txt('INTRO_SUB_'+suffix,540 if portrait else 408,560 if portrait else 578,width=935 if portrait else 656)
active(intro,0,5.12);active(sub,.42,5.12)
feed=txt('FEED_'+suffix,540 if portrait else 485,382 if portrait else 340,width=970 if portrait else 780)
fs=txt('FEED_SUB_'+suffix,540 if portrait else 392,540 if portrait else 484,width=920 if portrait else 630)
active(feed,5.08,8.26);active(fs,5.12,8.26)

rx,ry=(540,1060) if portrait else (1450,536)
rw=765 if portrait else 700
shadow=plane('Ground shadow',TEX/'DABIN__SHADOW__ROBOT.png',rx,ry+(340 if portrait else 285),width=850 if portrait else 790,z=.5)
active(shadow,0,8.25)
idle=plane('Robot idle',ASSETS/'DABIN__ROBOT__IDLE.png',rx,ry,width=rw,z=9)
key(idle,0,rx+350,ry+40,scale=0);key(idle,.7,rx,ry,scale=1)
key(idle,2.0,rx,ry-9,scale=1);key(idle,3.5,rx,ry,scale=1);key(idle,5.10,rx,ry-5,scale=1);key(idle,5.15,scale=0)
hungry=plane('Robot hungry',ASSETS/'DABIN__ROBOT__HUNGRY.png',rx,ry,width=rw,z=9)
active(hungry,5.10,7.94)
happy=plane('Robot delighted after save',ASSETS/'DABIN__ROBOT__DELIGHTED.png',rx,ry,width=rw,z=9)
active(happy,7.89,8.25)
for i,kind in enumerate(['LINK','NOTE','IMAGE']):
    t=5.12+i*.96
    x,y=(180+i*70,780) if portrait else (610,713)
    ob=plane('Flying '+kind,TEX/('DABIN__TOKEN__'+kind+'.png'),x,y,width=405 if portrait else 360,z=11)
    key(ob,0,scale=0);key(ob,t-.025,scale=0);key(ob,t+.10,x,y,scale=1)
    key(ob,t+.36,x+90,y-55,scale=1)
    mx=rx+rw*(414/902-.5);my=ry+rw*(350-364)/902
    key(ob,t+.79,mx,my,scale=.23);key(ob,t+.88,mx,my,scale=0)
saved=pill('SUCCESS',rx,ry+(450 if portrait else 355),width=230)
active(saved,7.91,8.25)

# Product views remain exact native screenshots. A slight presentation reveal
# animates the entire view; individual controls are never invented.
for label,filename,start,end in [('PROJECT','DABIN__UI__STUDIO_PROJECT.png',8.25,10.90),('SEARCH','DABIN__UI__SEARCH.png',10.90,14.30)]:
    path=ASSETS/filename
    if not path.exists() and label=='PROJECT':path=ASSETS/'DABIN__UI__PROJECTS.png'
    cx,cy=(540,1000) if portrait else (1230,530)
    width=1010 if portrait else 1200
    view=plane('Native '+label,path,cx,cy,width=width,z=6)
    active(view,start,end)
    title=txt(label+'_'+suffix,540 if portrait else 310,355 if portrait else 430,width=1000 if portrait else (540 if label=='PROJECT' else 570))
    active(title,start,end)
    note=txt('UI_NOTE_'+suffix,540 if portrait else 1210,1440 if portrait else 920,width=900 if portrait else 700)
    active(note,start,end)
    if label=='SEARCH':
        explain=txt('SEARCH_NOTE_'+suffix,540 if portrait else 300,560 if portrait else 670,width=900 if portrait else 430)
        active(explain,start,end)

endtitle=txt('END_'+suffix,540 if portrait else 550,415 if portrait else 381,width=1000 if portrait else 940)
endtag=txt('TAG_'+suffix,540 if portrait else 343,679 if portrait else 600,width=950 if portrait else 550)
active(endtitle,14.3,22.5);active(endtag,14.5,22.5)
finalrobot=plane('Robot final',ASSETS/'DABIN__ROBOT__DELIGHTED.png',540 if portrait else 1450,1110 if portrait else 550,width=720 if portrait else 690,z=9)
key(finalrobot,0,scale=0);key(finalrobot,14.3,scale=0);key(finalrobot,14.65,scale=1)
key(finalrobot,16.5,540 if portrait else 1450,1096 if portrait else 536,scale=1)
key(finalrobot,18.2,540 if portrait else 1450,1110 if portrait else 550,scale=1)
key(finalrobot,21.99,540 if portrait else 1450,1102 if portrait else 542,scale=1)
if portrait:
    coords=[(315,1480),(715,1480),(540,1600)]; widths=[180,285,535]
else:
    coords=[(190,774),(460,774),(805,774)];widths=[180,285,375]
for name,(x,y),w,start in zip(['FREE','ACCOUNT','LOCAL'],coords,widths,[14.48,15.48,17.0]):
    ob=pill(name,x,y,width=w);active(ob,start,22.5)

# Small frame metadata makes the edit honest and easy to inspect/revise.
scene['marketing_title']='Feed DaBin';scene['editorial_disclosure']='Editorial animation; real native UI, fictional isolated captures; not continuous screen recording.'
scene['ui_version']='0.4.31 (86)';scene['voice_provider']='ElevenLabs';scene['duration_seconds']=22
scene.frame_set(61)
bpy.ops.file.pack_all()
blend=HERE/('DABIN__FEED_DABIN__'+args.layout.upper()+'.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
work=KIT/'.work'/('frames_'+args.layout);work.mkdir(parents=True,exist_ok=True)
if args.frames:
    for frame in [int(x) for x in args.frames.split(',')]:
        scene.frame_set(frame);scene.render.filepath=str(work/('DABIN__FRAME__'+str(frame).zfill(4)+'.png'))
        bpy.ops.render.render(write_still=True)
elif args.render:
    scene.render.filepath=str(work/'DABIN__FRAME__')
    bpy.ops.render.render(animation=True)
print(json.dumps({'blend':str(blend),'layout':args.layout,'duration_seconds':22,'frames':660,'rendered':args.render or bool(args.frames)}))
