"""Per-variant emitter stations. Keep all corrections in model coordinates."""
from pathlib import Path
import json,numpy as np
from convert_widebody import SPECS,keep
from convert_models import read_ac
ROOT=Path(__file__).resolve().parents[1];MODELS=ROOT/'Sources/Winglight/Resources/Models'
core=ROOT/'Sources/WinglightCore/Resources/Aircraft.json';profiles=json.loads(core.read_text())
for specID,spec in SPECS.items():
 family=spec['family'];objs=[o for o in read_ac(ROOT/'ThirdParty/Widebody'/family/spec['file']) if o['faces']];selected=[o for o in objs if keep(o,family)]
 fus=max((o for o in selected if o['name'].lower()=='fuselage'),key=lambda o:len(o['vertices']));f=fus['vertices'];points=np.concatenate([o['vertices'] for o in selected]);cy=(f[:,1].min()+f[:,1].max())/2;rawWidth=np.ptp(f[:,2]);rawSpan=np.ptp(points[:,2]);xmin=points[:,0].min();xmax=points[:,0].max();bodyScale=spec['width']/rawWidth
 def pos(v):
  x,y,z=v;r=rawWidth/2;R=spec['width']/2;mag=abs(z);across=np.sign(z)*(mag*bodyScale if mag<=r else R+(mag-r)*(spec['span']/2-R)/(rawSpan/2-r))
  return [-float(across),float((y-cy)*bodyScale),float((x-(xmin+xmax)/2)*spec['length']/(xmax-xmin))]
 for profile in profiles:
  if not profile['id'].startswith(specID+'-'):continue
  lights=profile['lights']
  if family=='b787':
   def obj(name):return next(o['vertices'] for o in objs if o['name']==name)
   v=obj('lights.001');v=v[v[:,2]<0];tail=(v.min(0)+v.max(0))/2;tail[2]=v[:,2].min()-.035;tail[0]+=0.01;lights['tail']=pos(tail)
   v=obj('tlight');v=v[v[:,2]<0];nav=(v.min(0)+v.max(0))/2;nav[2]=v[:,2].min()-.035;lights['tailNav']=pos(nav)
   v=obj('ubeacon');p=(v.min(0)+v.max(0))/2;p[1]=v[:,1].max()+.025;lights['upper']=pos(p)
   v=obj('lbeacon');p=(v.min(0)+v.max(0))/2;p[1]=v[:,1].min()-.025;lights['lower']=pos(p)
   v=obj('logolts');v=v[v[:,2]<0];p=(v.min(0)+v.max(0))/2;p[1]=v[:,1].max()+.035;lights['logo']=pos(p)
   lights['logoTarget'][2]=lights['logo'][2]
  if specID=='a332':
   lights['tail']=pos([34.27,2.84668,0]);lights['logo'][2]=pos([27,2.36,-3.65])[2]+1.35;lights['logoTarget'][2]=pos([27.7,7.4,0])[2]+1.35
  # Locate top skin immediately below a logo lamp by exact triangle projection.
  mesh=np.fromfile(MODELS/(profile['id']+'.mesh'),dtype='<f4').reshape(-1,3,16)[:,:,:3]
  p=np.array(lights['logo']);a,b,c=mesh[:,0],mesh[:,1],mesh[:,2];v0=b-a;v1=c-a;v2=p-a
  den=v0[:,0]*v1[:,2]-v1[:,0]*v0[:,2];ok=abs(den)>1e-10;idx=np.where(ok)[0];den=den[ok]
  u=(v2[ok,0]*v1[ok,2]-v1[ok,0]*v2[ok,2])/den;v=(v0[ok,0]*v2[ok,2]-v2[ok,0]*v0[ok,2])/den
  valid=(u>=-1e-5)&(v>=-1e-5)&(u+v<=1.00001);ys=a[idx,1]+u*v0[idx,1]+v*v1[idx,1];ys=ys[valid]
  if len(ys):lights['logo'][1]=float(ys.max()+.035)
  path=MODELS/(profile['id']+'.json');report=json.loads(path.read_text());report['lights']=lights;path.write_text(json.dumps(report,indent=2))
# Rear-facing white wing position lamps: independent of the coloured forward lamps.
for profile in profiles:
 if profile['id']=='boeing' or profile['id'].startswith(('b77w-','b78')):
  mesh=np.fromfile(MODELS/(profile['id']+'.mesh'),dtype='<f4').reshape(-1,16)
  target=np.array(profile['lights']['strobe']);points=mesh[:,:3]
  candidates=points[(abs(points[:,0]-abs(target[0]))<.15)&(abs(points[:,1]-target[1])<1.2)]
  if len(candidates):
   p=candidates[candidates[:,2].argmax()].copy();p[2]+=.045;profile['lights']['wingRear']=p.tolist()
  reportPath=MODELS/(profile['id']+'.json')
  if reportPath.exists():
   report=json.loads(reportPath.read_text());report['lights']=profile['lights'];reportPath.write_text(json.dumps(report,indent=2))
core.write_text(json.dumps(profiles,indent=2));print('Calibrated',len(profiles),'assemblies')
