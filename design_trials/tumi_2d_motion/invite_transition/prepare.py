"""Approved neutral/invite endpoint blocking, on explicitly authorized copies.

Two forearm drawings are aligned in local arm coordinates before blending.
Hidden torso pixels come only from the local image_gen clean plate.
This is an art experiment, not a production animator or a generic image morph.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('rig_prepare', HERE.parent/'rig/prepare.py')
rig = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rig)
path_mask = rig.path_mask
FONT = ImageFont.truetype(str(ROOT/'assets/fonts/Nunito-Regular.ttf'), 18)


def rgba(path):
    return Image.open(path).convert('RGBA').resize((1024, 1024), Image.Resampling.LANCZOS)


def cut(im, mask):
    a = np.array(im)
    a[:, :, 3] = np.rint(a[:, :, 3].astype(float)*np.array(mask)/255).astype('uint8')
    return Image.fromarray(a)


def polygon(points, feather=1):
    im = Image.new('L', (4096, 4096))
    ImageDraw.Draw(im).polygon([(x*4, y*4) for x, y in points], fill=255)
    return im.resize((1024,1024), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(feather))


def blend(a,b,t):
    # Blend premultiplied color as well as coverage, avoiding dark alpha fringes.
    x,y=np.array(a).astype(float)/255,np.array(b).astype(float)/255
    alpha=x[:,:,3:]*(1-t)+y[:,:,3:]*t
    rgb=np.divide(x[:,:,:3]*x[:,:,3:]*(1-t)+y[:,:,:3]*y[:,:,3:]*t,
                  alpha,out=np.zeros_like(x[:,:,:3]),where=alpha>1e-8)
    return Image.fromarray(np.rint(np.concatenate([rgb,alpha],axis=2)*255).clip(0,255).astype('uint8'))


def affine(im, source_root, source_tip, root, tip):
    a,b=np.array(source_root,float),np.array(source_tip,float)
    c,d=np.array(root,float),np.array(tip,float)
    v,w=b-a,d-c
    u=v/np.linalg.norm(v); z=w/np.linalg.norm(w)
    # Longitudinal length can change; cross-sectional width is preserved.
    m=np.column_stack([z*np.linalg.norm(w)/np.linalg.norm(v),[-z[1],z[0]]]) @ np.column_stack([u,[-u[1],u[0]]]).T
    inv=np.linalg.inv(m); offset=a-inv@c
    return im.transform((1024,1024),Image.Transform.AFFINE,
                         (inv[0,0],inv[0,1],offset[0],inv[1,0],inv[1,1],offset[1]),Image.Resampling.BICUBIC)


def smooth(t):
    t=max(0,min(1,t)); return t*t*(3-2*t)


def local_arm(im, root, tip):
    root=np.array(root,float);axis=np.array(tip,float)-root
    axis/=np.linalg.norm(axis);normal=np.array([-axis[1],axis[0]])
    offset=root-normal*128-axis*64
    local=im.transform((256,256),Image.Transform.AFFINE,
        (normal[0],axis[0],offset[0],normal[1],axis[1],offset[1]),Image.Resampling.BICUBIC)
    pixels=np.array(local).astype(float)/255
    pixels[:,:,:3]*=pixels[:,:,3:]
    support=pixels[:,:,3]>=8/255
    ys=np.where(support.any(axis=1))[0]
    left=np.zeros(256);right=np.zeros(256)
    for y in ys:
        xs=np.where(support[y])[0];left[y]=xs[0];right[y]=xs[-1]
    return pixels,ys[0],ys[-1],left,right


def sample(pixels,x,y):
    x=x.clip(0,254.999);y=y.clip(0,254.999)
    ix=x.astype(int);iy=y.astype(int);dx=(x-ix)[...,None];dy=(y-iy)[...,None]
    return ((pixels[iy,ix]*(1-dx)+pixels[iy,ix+1]*dx)*(1-dy)+
            (pixels[iy+1,ix]*(1-dx)+pixels[iy+1,ix+1]*dx)*dy)


def forearm_morph(layers,t,root,angle):
    # Align BOTH silhouettes row by row before mixing their colors. An affine
    # alignment alone leaves two outlines because the approved drawings have
    # different widths and foreshortening. This controls the silhouette, but
    # does not invent anatomy or substitute for an authored intermediate pose.
    a,b=layers['_local0'],layers['_local1']
    yy,xx=np.mgrid[0:256,0:256].astype(float)
    lo=a[1]*(1-t)+b[1]*t;hi=a[2]*(1-t)+b[2]*t
    fraction=(yy-lo)/(hi-lo)
    ya=a[1]+fraction*(a[2]-a[1]);yb=b[1]+fraction*(b[2]-b[1])
    al=np.interp(ya,np.arange(256),a[3]);ar=np.interp(ya,np.arange(256),a[4])
    bl=np.interp(yb,np.arange(256),b[3]);br=np.interp(yb,np.arange(256),b[4])
    left=al*(1-t)+bl*t;right=ar*(1-t)+br*t
    across=(xx-left)/np.maximum(right-left,1)
    pa=sample(a[0],al+across*(ar-al),ya)
    pb=sample(b[0],bl+across*(br-bl),yb)
    pixels=pa*(1-t)+pb*t
    pixels[(fraction<0)|(fraction>1)|(across<-.04)|(across>1.04)]=0
    alpha=pixels[:,:,3:]
    pixels[:,:,:3]=np.divide(pixels[:,:,:3],alpha,out=np.zeros_like(pixels[:,:,:3]),where=alpha>1e-8)
    im=Image.fromarray(np.rint(pixels*255).clip(0,255).astype('uint8'))
    axis=np.array([math.cos(angle),math.sin(angle)]);normal=np.array([-axis[1],axis[0]])
    return im.transform((1024,1024),Image.Transform.AFFINE,
        (normal[0],normal[1],128-np.dot(normal,root),axis[0],axis[1],64-np.dot(axis,root)),Image.Resampling.BICUBIC)


def prepare():
    start=rgba(ROOT/'assets/mascot/core/tumi_neutral_front.png')
    end=rgba(ROOT/'assets/mascot/core/tumi_invite.png')
    clean=rgba(HERE/'sources/body-clean-plate.png')
    # Trace only the clean plate's torso boundary; generated checker pixels are
    # never used as an alpha channel. The approved head/ears/feet stay intact.
    torso=path_mask((391,534),[
        ((370,563),(351,622),(342,675)),
        ((330,730),(334,779),(354,823)),
        ((394,835),(451,840),(512,839)),
        ((581,840),(636,835),(671,823)),
        ((691,777),(691,724),(680,677)),
        ((672,617),(653,559),(632,534)),
        ((562,552),(461,552),(391,534)),
    ],.6)
    clean.putalpha(torso)
    left0=rgba(HERE.parent/'rig/layers/arm.png')
    # Shared elbow coverage makes the lower-arm rotation continuous at the join.
    lower=polygon([(270,617),(399,617),(410,758),(270,758)],4)
    upper=polygon([(270,520),(420,520),(420,664),(270,664)],4)
    left0lower=cut(left0,lower); left0upper=cut(left0,upper)
    left1mask=path_mask((390,537),[
        ((419,528),(445,539),(454,561)),
        ((471,592),(437,626),(412,649)),
        ((389,676),(359,681),(340,660)),
        ((317,636),(330,600),(347,574)),
        ((360,552),(376,542),(390,537)),
    ],.7)
    left1=cut(end,left1mask)
    right0mask=path_mask((626,535),[
        ((659,546),(690,596),(710,647)),
        ((724,684),(726,715),(706,725)),
        ((682,740),(662,716),(655,686)),
        ((645,643),(636,599),(615,552)),
        ((616,544),(622,538),(626,535)),
    ],.7)
    right1mask=path_mask((616,535),[
        ((646,539),(674,566),(694,602)),
        ((715,631),(717,656),(700,672)),
        ((680,692),(645,680),(626,661)),
        ((606,640),(599,600),(588,563)),
        ((592,548),(604,540),(616,535)),
    ],.7)
    right0=cut(start,right0mask); right1=cut(end,right1mask)
    # Repair follows the actual arm support. Rectangular repair ROIs remove
    # unrelated ear pixels: they are not a safe substitute for local masks.
    repair=Image.fromarray(np.maximum.reduce([
        np.array(left0.getchannel('A')),np.array(left1mask),
        np.array(right0mask),np.array(right1mask)]))
    repair=repair.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1))
    body0=Image.composite(clean,start,repair)
    body1=Image.composite(clean,end,repair)
    layers={'start':start,'end':end,'body0':body0,'body1':body1,
            'upper':left0upper,'fore0':left0lower,'fore1':left1,
            'right0':right0,'right1':right1,'repair':repair}
    out=HERE/'layers';out.mkdir(exist_ok=True)
    for name,im in layers.items(): im.save(out/f'{name}.png')
    layers['_local0']=local_arm(left0lower,(350,644),(330,702))
    layers['_local1']=local_arm(left1,(362,645),(423,568))
    return layers


def render(layers,t):
    # The two approved drawings define the exact held poses. Endpoint handoffs
    # are inspected separately; exact holds alone do not prove continuity.
    if t<=0:return layers['start'].copy()
    if t>=1:return layers['end'].copy()
    body=blend(layers['body0'],layers['body1'],t)
    elbow=np.array([350,644])*(1-t)+np.array([362,645])*t
    a0=math.atan2(702-644,330-350)
    a1=math.atan2(568-645,423-362)
    angle=a0+(a1-a0)*t
    upper=layers['upper'].copy()
    upper.putalpha(upper.getchannel('A').point(lambda a: round(a*(1-smooth((t-.6)/.4)))))
    body.alpha_composite(upper)
    body.alpha_composite(forearm_morph(layers,t,elbow,angle))
    root=np.array([634,555])*(1-t)+np.array([623,553])*t
    paw=np.array([690,699])*(1-t)+np.array([668,648])*t
    one=affine(layers['right0'],(634,555),(690,699),root,paw)
    two=affine(layers['right1'],(623,553),(668,648),root,paw)
    body.alpha_composite(blend(one,two,smooth(t)))
    return body


def main():
    sources=list((ROOT/'assets/mascot/core').glob('*.png'))
    before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    layers=prepare()
    board=Image.new('RGB',(1600,840),'#fffdf9');d=ImageDraw.Draw(board)
    values=[0,.001,.15,.3,.45,.6,.75,.9,.999,1]
    for i,t in enumerate(values):
        out=Image.new('RGBA',(1024,1024),'#39464b');out.alpha_composite(render(layers,t))
        board.paste(out.convert('RGB').resize((320,320),Image.Resampling.LANCZOS),(i%5*320,i//5*420))
        d.text((i%5*320+12,i//5*420+324),f'pose progress {t:.3f}',font=FONT,fill='#453229')
    board.save(HERE/'blocking-contact.png')
    # A baked atlas is solely for reviewing this art experiment on a simulator;
    # it is not the proposed wardrobe pipeline and does not set app FPS.
    poses=[render(layers,i/30) for i in range(31)]
    atlas=Image.new('RGBA',(384*8,384*4))
    for i,im in enumerate(poses):
        atlas.paste(im.resize((384,384),Image.Resampling.LANCZOS),(i%8*384,i//8*384))
    atlas.save(HERE/'pose-atlas.png')
    flat=[]
    for im in poses:
        bg=Image.new('RGBA',(1024,1024),'#39464b');bg.alpha_composite(im)
        flat.append(bg.convert('RGB').resize((384,384),Image.Resampling.LANCZOS))
    palette_source=Image.new('RGB',(384*3,384))
    for i,n in enumerate([0,15,30]):palette_source.paste(flat[n],(i*384,0))
    palette=palette_source.quantize(colors=256)
    frames=[]
    for ms in range(0,4200,40):
        t=0 if ms<600 else smooth((ms-600)/1200) if ms<1800 else 1 if ms<2400 else 1-smooth((ms-2400)/1200) if ms<3600 else 0
        frames.append(flat[round(t*30)].quantize(palette=palette,dither=Image.Dither.NONE))
    frames[0].save(HERE/'motion.gif',save_all=True,append_images=frames[1:],duration=40,loop=0,disposal=2,optimize=False)
    def rgb(im):
        bg=Image.new('RGBA',(1024,1024),'#39464b');bg.alpha_composite(im)
        return np.array(bg.convert('RGB')).astype(float)
    mask=np.array(layers['repair'])==0
    report={'approved_sources_sha256':{Path(p).name:v for p,v in before.items()},
        'source_unchanged':True,'atlas':{'tile':384,'columns':8,'count':31},
        'preview_duration_ms':4200,'gif_sampling_fps':25,
        'not_a_display_fps_benchmark':True,
        'outside_repair_changed_pixels':{str(i):int(np.count_nonzero(np.any(np.array(layers[f'body{i}'])!=np.array(layers['start' if i==0 else 'end']),axis=2)&mask)) for i in [0,1]},
        'endpoint_handoff_mean_rgb_difference':{
            'start_to_progress_0001':float(np.abs(rgb(poses[0])-rgb(render(layers,.001))).mean()),
            'progress_0999_to_end':float(np.abs(rgb(render(layers,.999))-rgb(poses[-1])).mean())},
        'limitations':['Exact held endpoints draw original images; this alone does not prove seamless handoff.',
                      'Forearm overlap and shoulder shading remain art-review items.',
                      'No new outfit, MI performance, whole-body rig or production integration.']}
    (HERE/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    assert before=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    print('Prepared layer copies and contact; all approved originals unchanged.')


if __name__=='__main__':main()
