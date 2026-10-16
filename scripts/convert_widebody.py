"""Import independent upstream widebody assemblies, preserving every UV island.
Source coordinates: x aft, y up, z port. Output: x starboard, y up, z aft, metres.
Only published envelope constraints are calibrated; this is not a CAD model.
"""
from pathlib import Path
import json,re,hashlib,copy,sys,xml.etree.ElementTree as ET
import numpy as np
from convert_models import read_ac,subdivide_surface,mesh,build_bvh
ROOT=Path(__file__).resolve().parents[1];SRC=ROOT/'ThirdParty/Widebody';DEST=ROOT/'Sources/Winglight/Resources/Models'
SPECS={
 'b788':dict(family='b787',file='787-8.ac',length=56.72,span=60.12,width=5.77,engines=['genx','trent']),
 'b789':dict(family='b787',file='787-9.ac',length=62.81,span=60.12,width=5.77,engines=['genx','trent']),
 'b78x':dict(family='b787',file='787-10.ac',length=68.28,span=60.12,width=5.77,engines=['genx','trent']),
 'a332':dict(family='a330',file='a330-200-main.ac',length=58.82,span=60.30,width=5.64,engines=['rr','pw','ge']),
 'a333':dict(family='a330',file='a330-300-main.ac',length=63.66,span=60.30,width=5.64,engines=['rr','pw','ge']),
 'a359':dict(family='a350',file='A350XWB-900.ac',length=66.80,span=64.75,width=5.94,engines=['xwb']),
 'b77w':dict(family='b777',file='777-300.ac',length=73.86,span=64.80,width=6.20,engines=['ge90']),
}
ENGINES={'genx':'GEnx.ac','trent':'Trent1000.ac','rr':'trent772b-60.ac','pw':'pw4000.ac','ge':'cf6-80e1.ac'}
def keep(o,family):
 n=o['name'].lower();t=o['texture'];v=o['vertices']
 if not o['faces']:return False
 if family=='b787':
  if t=='landing-gears.png' or n in ['windows-bright','wifiantenna']:return False
  if any(k in n for k in ['beacon','navlite','turnoff','landlt','ltcover','tlight','winglts','lights.']):return False
  # Full static blade stages, never duplicate spinning disks.
  if n in ['eng1fan1','eng2fan1','lhfans','rhfans','lhfan','rhfan']:return False
 if family=='a330':
  if t=='landing-gears.png' and not n.startswith('landing-'):return False
  if n in ['sphere','land-light-l','land-light-r','noseradio'] or 'slat.in.open' in n:return False
  if '.fanblur' in n:return False
 if family=='a350':
  if t=='landinggear.png' or n.startswith(('fan2_','lamp','left.wing.lamp','right.wing.lamp')):return False
  # Remove only the stray editing cube; retain the 120 actual glazing panes.
  if n=='cabin.windows':
   o['faces']=[f for f in o['faces'] if np.all(v[f[0],1]>1.8) and np.all(abs(v[f[0],2])<3.1)]
   used=np.unique([i for f in o['faces'] for i in f[0]]);remap={int(i):k for k,i in enumerate(used)}
   o['vertices']=v[used];o['faces']=[([remap[i] for i in ids],flags,uv) for ids,flags,uv in o['faces']]
 if family=='b777':
  # Optional upstream window-mix overlay is selected only by a cabin switch;
  # importing it as opaque glass creates coplanar patches over the normal row.
  if n.startswith('window mix'):return False
  if t not in ['']+[f'AFR{i}.png' for i in range(1,10)]+['AFR1rac.png','windowmix.png']:return False
  if t=='AFR9.png':return False # gear in deployed authoring pose
  if any(k in n for k in ['flash','strobe','beacon','navlight','redlight','taxi','ctrlnd','heli','rat','lumiere','wiperglace']):return False
  if n.startswith(('fuselagelumiere','window mix interieur')):return False
  if not t and n!='glassehublot' and not re.fullmatch(r'entry[1-5][lr]g',n):return False
 return True

def assign(o,family,engine,slots):
 n=o['name'].lower();t=o['texture'];part=2
 if family=='b787':
  if o['file'] in ['GEnx.ac','Trent1000.ac']:
   t='engine';part=4
   if n.startswith(('eng1fan','eng2fan')):part=6
   if n=='front':part=8
  else:
   if t.endswith('.png') and t not in ['wings.png','Window.png','windows-dim.png']:t='paint'
   if n in ['window','windows-dim']:part=13 if n=='windows-dim' else 5;t=''
   elif n in ['fin','rudder']:part=3
   elif n.startswith(('fuselage','bodyfairing','aftcargo','fwdcargo','bulkcargo')):part=1
   elif 'chrome' in n:part=12;t=''
 elif family=='a330':
  if 'blank.png' in t:t='paint'
  if n in ['fuselage','nosecone','bellyfairing'] and np.ptp(o['vertices'][:,0])>1:part=1
  if n in ['vstab','rudder']:part=3
  if o['file'] in ENGINES.values():part=4
  if n.startswith('fan'):part=6
  if '.rim' in n or n=='intake':part=8
  if n=='windshield':part=5;t=''
  if t=='windshield_pane.png':part=7;t=''
 elif family=='a350':
  if t=='a350xwb.png':t='paint'
  if n=='cabin.windows':part=13;t=''
  if n.startswith('fuselage'):part=1
  if n in ['rudderfront','rudder']:part=3
  if n=='windshield':part=5;t=''
  if n=='nacelle' or 'eng' in n or n in ['cube.004','cube.030']:part=4
  if n.startswith(('fan_eng','cone_eng')):part=6
  if n=='engine_chrome':part=8
 elif family=='b777':
  if n.startswith(('fuselage','entry','lfdoor','lrdoor','rfdoor','rrdoor')):part=1
  if n in ['tail','rudder','lrudder']:part=3
  if any(k in n for k in ['engchrome','moteur','reverser','inlets','fan','cage','clapet']):part=4
  if n in ['lfan','rfan']:part=6
  if n=='lhengchrome':part=8
  if n=='glassehublot' or n.startswith('glass') or re.fullmatch(r'entry[1-5][lr]g',n):part=5;t=''
  if n=='glassehublot':part=13
 if 'wiper' in n:part=9;t=''
 if t and t not in slots:slots.append(t)
 o['part']=part;o['textureIndex']=10+slots.index(t) if t else 0

def stow_a350(objs,folder):
 # Evaluate original gear-door rotations at gear=0, before metre calibration.
 # FlightGear's x/y/z = AC x/-z/y, a proper orthogonal basis.
 xml=ET.parse(folder/'A350XWB-900.xml')
 def vector(node):
  return np.array([float(node.findtext('x-m',node.findtext('x','0'))),float(node.findtext('z-m',node.findtext('z','0'))),-float(node.findtext('y-m',node.findtext('y','0')))])
 for a in xml.findall('.//animation'):
  if a.findtext('type')!='rotate' or not (a.findtext('property') or '').startswith('gear/'):continue
  names=[e.text for e in a.findall('object-name')];selected=[o for o in objs if o['name'] in names and 'door' in o['name'].lower()]
  if not selected:continue
  entries=sorted((float(e.findtext('ind')),float(e.findtext('dep')))for e in a.findall('interpolation/entry'))
  angle=entries[0][1] if entries else float(a.findtext('offset-deg','0'))
  if abs(angle)<1e-6:continue
  axis=a.find('axis');center=a.find('center')
  if center is None or axis is None:continue
  c=vector(center);v=vector(axis);v/=np.linalg.norm(v);rad=np.deg2rad(angle)
  for o in selected:
   q=o['vertices']-c;o['vertices']=c+q*np.cos(rad)+np.cross(v,q)*np.sin(rad)+np.outer(q@v,v)*(1-np.cos(rad))

def convert(key,spec,engine):
 family=spec['family'];folder=SRC/family
 objs=[o for o in read_ac(folder/spec['file']) if keep(o,family)]
 if family=='b777':
  # The six cockpit panes live in the upstream interior submodel. Import only
  # its glazing, using the exact offset declared by flightdeck-300.xml.
  offset=float(ET.parse(folder/'flightdeck-300.xml').findtext('offsets/x-m'))
  panes=[o for o in read_ac(folder/'flightdeck.ac') if o['texture']=='glass-alpha.png']
  assert sum(len(o['faces']) for o in panes)==6
  for o in panes:o['vertices'][:,0]+=offset
  objs+=panes
 if engine in ENGINES:objs += [o for o in read_ac(folder/ENGINES[engine]) if keep(o,family)]
 if family=='a350':stow_a350(objs,folder)
 slots=[]
 for o in objs:assign(o,family,engine,slots)
 fus=max((o for o in objs if o['name'].lower()=='fuselage'),key=lambda o:len(o['vertices']))
 f=fus['vertices'];rawWidth=np.ptp(f[:,2]);cy=(f[:,1].max()+f[:,1].min())/2
 points=np.concatenate([o['vertices'] for o in objs]);xmin=points[:,0].min();xmax=points[:,0].max();rawSpan=np.ptp(points[:,2]);xs=spec['length']/(xmax-xmin);bodyScale=spec['width']/rawWidth
 def position(v):
  v=np.array(v,dtype=float);side=v[...,2];mag=np.abs(side);r=rawWidth/2;R=spec['width']/2
  across=np.sign(side)*np.where(mag<=r,mag*bodyScale,R+(mag-r)*(spec['span']/2-R)/(rawSpan/2-r))
  return np.stack([-across,(v[...,1]-cy)*bodyScale,(v[...,0]-(xmin+xmax)/2)*xs],axis=-1)
 for o in objs:o['vertices']=position(o['vertices'])
 fanobjs=[o for o in objs if o['part']==6];fp=np.concatenate([o['vertices'] for o in fanobjs]);side=fp[fp[:,0]>0];engineXY=[float((side[:,0].min()+side[:,0].max())/2),float((side[:,1].min()+side[:,1].max())/2)]
 for o in fanobjs:o['fanCenter']=[np.sign(o['vertices'][:,0].mean())*engineXY[0],engineXY[1]]
 # Preserve openings and source UV boundaries; smooth only real skin surfaces.
 for o in objs:
  n=o['name'].lower();levels=0
  if o is fus:levels=2 if family=='b777' else 3
  elif n in ['nosecone','nacelle'] or n.startswith(('no1enge','no2enge')):levels=2
  elif o['part']==4 and ('.nacelle' in n or '.reverser.' in n):levels=2
  if levels:subdivide_surface(o,levels)
 data,audit=mesh(objs,'generic');assert np.isfinite(data).all();assert np.all(abs(np.linalg.norm(data[:,4:7],axis=1)-1)<.02)
 ident=key+'-'+engine;path=DEST/(ident+'.mesh');path.write_bytes(data.tobytes());build_bvh(data,DEST/(ident+'.bvh'))
 render=data[:,:3];actual=[float(np.ptp(render[:,2])),float(np.ptp(render[:,0])),float(np.ptp(fus['vertices'][:,0]))]
 target=[spec['length'],spec['span'],spec['width']];assert all(abs(a-b)<.005 for a,b in zip(actual,target)),(ident,actual,target)
 # Positions read from source light assemblies. z-up XML offsets are converted
 # to AC axes before passing through the same calibration as the visible mesh.
 if family=='b787':
  nav=[9.71,3.48,-27.30];strobe=[9.91,3.52,-27.51];upper=[-17.04,4.64,0];lower=[-10.31,-1.83,0];landing=[-7.29,.36,-3.37];logo=[29.06,2.73,-4.60];tail=[31.03,2.13,0];targetP=[29,8.5,0]
 elif family=='a330':
  nav=[12.764,.99,-28.821];strobe=[12.88,1.0,-28.86];upper=[7.34,3.39,0];lower=[-5.08,-3.09,0];landing=[-1.96,-1.31,-3.52];logo=[31.7,2.36,-3.65];tail=[37.6,2.2,0];targetP=[32.4,7.4,0]
  if key=='a332':
   # Tail and beacon stations differ on the shortened assembly.
   logo[0]-=4.7;tail[0]-=4.7;targetP[0]-=4.7
 elif family=='a350':
  nav=[42.7,3.44,-30.82];strobe=[42.96,3.46,-30.86];upper=[25.60,4.72,0];lower=[34.36,-2.35,0];landing=[22.18,-.30,-3.8];logo=[60.4,3.05,-3.8];tail=[65.55,2.4,0];targetP=[61.5,9,0]
 else:
  nav=[15.56,1.73,-31.12];strobe=[15.65,1.75,-31.18];upper=[0,3.28,0];lower=[-6.22,-3.64,0];landing=[-3.55,-1.45,-3.9];logo=[36.5,1.93,-4];tail=[42.86,1.28,0];targetP=[37.3,8.8,0]
 lights={n:position(v).tolist() for n,v in [('nav',nav),('strobe',strobe),('upper',upper),('lower',lower),('landing',landing),('logo',logo),('tail',tail),('logoTarget',targetP)]}
 hs=[o['vertices'] for o in objs if o['name'].lower() in ['hstab','hstab.003','lstab','rstab','lhstab','rhstab']];tailSpan=float(np.ptp(np.concatenate(hs)[:,0]))
 report={'id':ident,'aircraft':key,'family':family,'engine':engine,'length':spec['length'],'span':spec['span'],'bodyWidth':spec['width'],'tailSpan':tailSpan,'engineXY':engineXY,'bodyCenterY':0,'finHeight':float(render[:,1].max()),'lights':lights,'textureSlots':slots,'triangles':len(data)//3,'vertices':len(data),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'constraints':[{'name':n,'target':t,'actual':a} for n,t,a in zip(['length','span','bodyWidth'],target,actual)],'objects':audit}
 (DEST/(ident+'.json')).write_text(json.dumps(report,indent=2));print(ident,len(data)//3,slots,flush=True)
 return report
if __name__=='__main__':
 wanted=sys.argv[1:];profiles=[]
 for key,spec in SPECS.items():
  for engine in spec['engines']:
   ident=key+'-'+engine
   if wanted and key not in wanted and ident not in wanted:continue
   profiles.append(convert(key,spec,engine))
 catalog=[]
 for key,spec in SPECS.items():
  for engine in spec['engines']:
   p=DEST/(key+'-'+engine+'.json')
   if p.exists():catalog.append(json.loads(p.read_text()))
 (DEST/'widebody.json').write_text(json.dumps(catalog,indent=2))
