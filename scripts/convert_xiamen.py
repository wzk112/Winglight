from pathlib import Path
import numpy as np,json,hashlib,shutil,sys
r=Path(__file__).resolve().parents[1];m=r/'Sources/Winglight/Resources/Models';l=r/'Sources/Winglight/Resources/Liveries';w=r/'ThirdParty/GeoFS';v=np.fromfile(m/'b789-genx.mesh',dtype='<f4').reshape(-1,16).copy()
# Preserve detailed geometry, only adapt UVs to the source side projections.
# Side-specific V bands preserve readable mirrored starboard atlas lettering.
x,y,z=v[:,0],v[:,1],v[:,2];left=x<0
body=(v[:,14]==10)&(v[:,15]==1)
u=(z+31.405)/(29.132349+31.405)*.971+.006
vv=.185-(y+.05)/2.99*.049
v[body,12]=np.clip(u[body],.006,.977);v[body,13]=vv[body]+np.where(left[body],0,.235)
v[body,14]=13
# Fin projected in the atlas. Mapping the leading/trailing edges separately
# follows the swept silhouette and keeps the emblem away from empty background.
fin=v[:,15]==3;fy=y[fin];h=np.clip((fy-2.6)/(11.79755-2.6),0,1)
# Cross-sections of the real fin, not its bounding rectangle.
tri=v.reshape(-1,3,16);ft=tri[np.all(tri[:,:,15]==3,axis=1),:,:3]
levels=np.linspace(1.57,11.796,256);low=[];high=[]
for level in levels:
 hits=[]
 for a,b in [(0,1),(1,2),(2,0)]:
  ya=ft[:,a,1];yb=ft[:,b,1];ok=((ya<=level)&(yb>=level)|(yb<=level)&(ya>=level))&(abs(ya-yb)>1e-8)
  t=(level-ya[ok])/(yb[ok]-ya[ok]);hits.extend((ft[ok,a,2]+t*(ft[ok,b,2]-ft[ok,a,2])).tolist())
 low.append(min(hits)if hits else 29);high.append(max(hits)if hits else 30)
zlead=np.interp(fy,levels,low);ztrail=np.interp(fy,levels,high)
uLead=.834+.123*h;uTrail=.945+.053*h
v[fin,12]=uLead+np.clip((z[fin]-zlead)/np.maximum(ztrail-zlead,.01),0,1)*(uTrail-uLead)
v[fin,13]=.136-h*.129+np.where(left[fin],0,.235);v[fin,14]=13
# Source side art contains its own cabin windows. Remove the detached native
# window overlays so the two differently spaced window rows cannot overlap.
audit=json.loads((m/'b789-genx.json').read_text());keep=np.ones(len(v),dtype=bool);start=0
for obj in audit['objects']:
 end=start+obj['triangles']*3
 if obj['name']=='windows-dim':keep[start:end]=False
 start=end
v=v[keep]
ident='b789-genx-cxa';(m/(ident+'.mesh')).write_bytes(v.tobytes());sys.path.insert(0,str(r/'scripts'));from convert_models import build_bvh;build_bvh(v,m/(ident+'.bvh'))
info=json.loads((m/'b789-genx.json').read_text());info['id']=ident;info['textureSlots'].append('projection');info['triangles']=len(v)//3;info['vertices']=len(v);info['sha256']=hashlib.sha256(v.tobytes()).hexdigest();info['adaptation']='Original 2K GeoFS side projections on detailed GEnx exterior; approximate UV transfer.'
info['objects']=[o for o in info['objects'] if o['name']!='windows-dim']
(m/(ident+'.json')).write_text(json.dumps(info,indent=2))
if '--mesh-only' in sys.argv:sys.exit(0)
p=r/'Sources/WinglightCore/Resources/Aircraft.json';items=json.loads(p.read_text());items=[q for q in items if q['id']!=ident];items.append({k:info[k] for k in items[0]});p.write_text(json.dumps(items,indent=2))
sys.path.insert(0,str(r/'scripts'));import fetch_widebody_liveries as fetch
paint,ps=fetch.fetch('787','Models/787-9.png');engine,es=fetch.fetch('787','Models/Liveries-engines/GEnx.png');wing,ws=fetch.fetch('787','Models/wings.png')
cat=json.loads((l/'catalog.json').read_text());cat=[q for q in cat if not q['id'].startswith('b789-genx-CXA')]
for key,title in [('xiamen','厦门航空'),('xiamenun','厦门航空 · 联合梦想号')]:
 src=w/(key+'.webp');dst=l/('geofs-'+key+'.webp');shutil.copyfile(src,dst)
 cat.append(dict(id='b789-genx-CXA'+('-UN' if key=='xiamenun' else ''),code='CXA',title=title,english='XiamenAir'+(' United Dream' if key=='xiamenun' else ''),region='中国',aircraft='b789',model=ident,texture=dst.name,textures=[paint,wing,engine,dst.name],engineTexture=None,resolution=2048,note='GEnx · 原始 2K · 投影适配；局部细节与原机有差异',special=key=='xiamenun',sources=[ps,ws,es,dict(file=dst.name,url='https://raw.githubusercontent.com/kolos26/GEOFS-LiverySelector/bd05e90779060883a28b467a577077628c8b355c/liveries/boeing_b787-9/'+key+'.webp',sha256=hashlib.sha256(src.read_bytes()).hexdigest(),size=[2048,2048],bytes=src.stat().st_size)],credit='B-20AJ / TCA Design; GeoFS LiverySelector'))
(l/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2))
print('Added Xiamen projection liveries')
