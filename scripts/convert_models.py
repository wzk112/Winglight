"""Build calibrated, UV-preserving exterior meshes from the bundled GPL-2 AC3D sources.
Run with Python 3 + NumPy. Air China texture provenance is recorded in ThirdParty/NOTICE.txt.
Coordinates: x starboard, y up, z aft; metres. See MODEL_ACCURACY.md.
"""
from pathlib import Path
import io, shlex, json, struct, hashlib, sys
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT/'Sources/Winglight/Resources/Models'

def read_ac(path):
    stream=io.BytesIO(path.read_bytes()); objects=[]
    def line(): return stream.readline().decode('utf-8',errors='replace').strip()
    def obj(parent):
        start=line(); assert start.startswith('OBJECT '),start
        o={'name':'unnamed','loc':np.zeros(3),'rot':np.eye(3),'vertices':[], 'faces':[], 'texture':'', 'crease':45.0}
        while True:
            p=shlex.split(line())
            if not p: continue
            k=p[0]
            if k=='name': o['name']=p[1]
            elif k=='texture': o['texture']=p[1]
            elif k=='crease': o['crease']=float(p[1])
            elif k=='loc': o['loc']=np.array(list(map(float,p[1:])))
            elif k=='rot': o['rot']=np.array(list(map(float,p[1:]))).reshape(3,3)
            elif k=='data': stream.read(int(p[1]))
            elif k=='numvert': o['vertices']=np.array([list(map(float,line().split())) for _ in range(int(p[1]))])
            elif k=='numsurf':
                for _ in range(int(p[1])):
                    flags=0
                    while True:
                        q=line().split()
                        if q[0]=='SURF': flags=int(q[1],0)
                        if q[0]=='refs':
                            rows=[line().split() for _ in range(int(q[1]))]
                            refs=[int(r[0]) for r in rows]; uv=[[float(r[1]),1-float(r[2])] for r in rows]
                            if flags&15==0 and len(refs)>=3: o['faces'].append((refs,flags,uv))
                            break
            elif k=='kids':
                transform=np.eye(4);transform[:3,:3]=o['rot'];transform[:3,3]=o['loc'];transform=parent@transform
                if len(o['vertices']):
                    o['vertices']=o['vertices']@transform[:3,:3].T+transform[:3,3];o['file']=path.name;objects.append(o)
                for _ in range(int(p[1])): obj(transform)
                break
    while True:
        pos=stream.tell();s=line()
        if s.startswith('OBJECT '): stream.seek(pos);obj(np.eye(4));break
        if not s and stream.tell()==len(stream.getbuffer()): raise ValueError('Missing root')
    return objects

def selected(o,a):
    n=o['name'];l=n.lower()
    # Lens covers are represented by the emitter pass, not opaque occluders.
    if n in ['navglass','a-light','a-light1']:return False
    if a=='airbus':
        if any(x in l for x in ['placard','sharklet','spinning','actuator','uld45','cables','sidestay','nurbspath','ratspinner']): return False
        if n=='Rat' or l.endswith('.inner') and not l.startswith('enginecfm'): return False
        if n.startswith(('MLG','NLG','GearL')) and n not in ['MLGGearDoorL','MLGGearDoorR','NLGAftDoorL','NLGAftDoorR','NLGForewardDoorL','NLGForewardDoorR']: return False
    else:
        if l.startswith(('mg','lhdrag','rhdrag','sidestrut','rhsidestrut','lhgd','rhgd','geardoor','ngww')):return False
        if l.startswith('dorrhfront_0'):return False
    return bool(o['faces'])

def calibrate(objects,a):
    if a=='airbus':
        length=37.57;span=34.10;tail=12.45;body=3.95;center=.001055;bodyScale=body/3.97547
        rawL=37.6058;wing=17.05
        hs=np.concatenate([o['vertices'] for o in objects if o['name'] in ['Hstabs','ElevatorL','ElevatorR']]); hcenter=(hs[:,2].max()+hs[:,2].min())/2;hscale=tail/np.ptp(hs[:,2])
        for o in objects:
            v=o['vertices'].copy();n=o['name'];long=v[:,0]*length/rawL
            side=v[:,2]-center;mag=np.abs(side)
            side=np.sign(side)*np.where(mag<2.18,mag*bodyScale,2.18*bodyScale+(mag-2.18)*(span/2-2.18*bodyScale)/(wing-2.18))
            if n in ['Hstabs','ElevatorL','ElevatorR']:side=(v[:,2]-hcenter)*hscale
            if o['file']=='CFM56.ac':
                sign=np.sign(v[:,2].mean());side=v[:,2]+sign*(5.75-5.63082)
                long=(v[:,0]+7.50198)-length/2+11.19
            o['vertices']=np.column_stack([-side,v[:,1],long])
        # Restore exactly symmetric specified wing span after source centre offset.
        fences=[o for o in objects if o['name']=='WingtipFence']
        for o in fences:
            v=o['vertices'];v[:,0]-=(v[:,0].max()+v[:,0].min())/2;v[:,0]*=span/np.ptp(v[:,0])
    else:
        length=39.47;span=35.79;tail=14.35;body=3.76;center=.01725;bodyScale=body/3.72378
        hs=np.concatenate([o['vertices'] for o in objects if o['file']=='HorzStab.ac']);hcenter=(hs[:,2].max()+hs[:,2].min())/2;hscale=tail/np.ptp(hs[:,2]);hx0=hs[:,0].min();hx1=hs[:,0].max()
        for o in objects:
            v=o['vertices'].copy();n=o['name'].lower();long=(v[:,0]+19.80998)*38.02/38.08-length/2
            side=v[:,2]-center;mag=np.abs(side)
            side=np.sign(side)*np.where(mag<1.9,mag*bodyScale,1.9*bodyScale+(mag-1.9)*(span/2-1.9*bodyScale)/(17.845-1.9))
            if o['file']=='HorzStab.ac':
                side=(v[:,2]-hcenter)*hscale
                root=(hx0+19.80998)*38.02/38.08-length/2
                long=root+(v[:,0]-hx0)*(length/2-root)/(hx1-hx0)
            if o['file'] in ['LWing.ac','RWing.ac'] and any(x in n for x in ['eng','duct','fan','reverser','tailpipe','fwdpylon']):
                sign=np.sign(v[:,2].mean());side=v[:,2]+sign*(4.83-5.164)
                long=(v[:,0]+6.23284)-length/2+13.36
            o['vertices']=np.column_stack([-side,v[:,1],long])
        for o in objects:
            if o['file']=='winglet.ac' and o['name']=='WingletL':
                v=o['vertices'];v[:,0]-=(v[:,0].max()+v[:,0].min())/2;v[:,0]*=span/np.ptp(v[:,0])
    return length,span,tail,body

def triangulate(refs,v):
    # Ear clipping in the polygon's dominant plane, including concave AC3D faces.
    p=v[refs];normal=np.sum(np.cross(p,np.roll(p,-1,axis=0)),axis=0)
    q=np.delete(p,int(np.argmax(np.abs(normal))),axis=1)
    cross=lambda a,b: a[0]*b[1]-a[1]*b[0]
    winding=1 if sum(cross(q[i],q[(i+1)%len(q)]) for i in range(len(q)))>=0 else -1
    ids=list(range(len(refs)));out=[]
    while len(ids)>3:
        found=False
        for j in range(len(ids)):
            a,b,c=ids[j-1],ids[j],ids[(j+1)%len(ids)]
            turn=cross(q[b]-q[a],q[c]-q[b])*winding
            if abs(turn)<1e-12: ids.pop(j);found=True;break
            if turn<0:continue
            def inside(k):
                return all(cross(q[y]-q[x],q[k]-q[x])*winding>1e-12 for x,y in [(a,b),(b,c),(c,a)])
            if any(inside(k) for k in ids if k not in [a,b,c]):continue
            out.append([refs[a],refs[b],refs[c]]);ids.pop(j);found=True;break
        if not found:
            # Bridged aperture rings in the 777 source repeat boundary points.
            # Earcut handles these weakly-simple contours without a centroid fan.
            import mapbox_earcut
            indices=mapbox_earcut.triangulate_float64(np.ascontiguousarray(q,dtype=np.float64),np.array([len(q)],dtype=np.uint32)).reshape(-1,3)
            triangles=[]
            for a,b,c in indices:
                if cross(q[b]-q[a],q[c]-q[a])*winding<0:b,c=c,b
                triangles.append([refs[a],refs[b],refs[c]])
            if not triangles:raise ValueError('Untriangulatable polygon')
            return triangles
    if len(ids)==3:out.append([refs[i] for i in ids])
    return out

def upgrade_737_details(objects):
    """Use actual later upstream engine/blade and passenger-glass geometry."""
    for filename in ['LWing.ac','RWing.ac']:
        old=[o for o in objects if o['file']==filename]
        donor=read_ac(ROOT/'ThirdParty/737YV'/filename)
        engine=lambda o:any(k in o['name'].lower() for k in ['eng','duct','fan','reverser','tailpipe','fwdpylon'])
        old_engine=[o for o in old if engine(o)]
        new_engine=[o for o in donor if engine(o)]
        # Match the inlet station and fan axis before the manufacturer-based
        # assembly calibration. The later upstream assembly is offset in x/y.
        old_lip=next(o for o in old_engine if o['name'] in ['engnose','engnose.003'])
        new_lip=next(o for o in new_engine if o['name'] in ['engnose','engnose.003'])
        shift=old_lip['vertices'].min(0)-new_lip['vertices'].min(0)
        # The donor's right assembly is offset laterally as well. A lip's
        # asymmetric bounding box is not the rotor axis (the 737 inlet is flat
        # underneath). Align the circular fan, moving the whole engine together.
        fan=next(o for o in new_engine if o['name'].lower()=='fan')
        axis=(fan['vertices'].min(0)+fan['vertices'].max(0))*.5
        shift[1]=-1.20-axis[1]
        shift[2]=np.sign(axis[2])*5.164-axis[2]
        for o in new_engine:
            o['vertices']+=shift;o['source']='737YV/'+filename
        objects[:]=[o for o in objects if not (o['file']==filename and engine(o))]+new_engine
    glazing=[o for o in read_ac(ROOT/'ThirdParty/737YV/737-800.ac') if o['name']=='rearwindows.ext']
    for o in glazing:o['source']='737YV/737-800.ac'
    objects[:]=[o for o in objects if o['name'] not in ['windowslh','windowsrh']]+glazing


def add_737_compressor_backstops(objects):
    """Opaque interior behind the fan, not a view-facing overlay.

    The donor exterior leaves a sightline from blade gaps to the far cowl and
    sky. A dark compressor backing closes that path within each intake. This
    is a visual interior approximation, not an engineering compressor model.
    """
    for fan in [o for o in objects if o['name'].lower()=='fan']:
        v=fan['vertices'];low=v.min(0);high=v.max(0);center=(low+high)*.5
        radius=max(high[0]-low[0],high[1]-low[1])*.5
        z=high[2]+.035;count=96
        vertices=[[center[0],center[1],z]]+[[center[0]+radius*np.cos(a),center[1]+radius*np.sin(a),z] for a in np.linspace(0,2*np.pi,count,endpoint=False)]
        faces=[([0,i+1,(i+1)%count+1],0,[[0,0]]*3) for i in range(count)]
        objects.append(dict(name='engcore-backing-'+str(int(np.sign(center[0]))),file='procedural',source='Winglight compressor backing',texture='',vertices=np.array(vertices),faces=faces,part=4))


def subdivide_surface(o,levels):
    """Catmull-Clark on source polygons, with welded UV seams and locked joins.

    The old triangle midpoint displacement retained a highlight ripple at every
    original control edge. Here original interior control points also converge
    to the smooth limit surface. Apertures, hard edges and component joins are
    fixed, so glass/door seams remain closed. UVs are face-varying attributes.
    """
    original=o['vertices'];bounds=(original.min(0),original.max(0))
    v,first,remap=np.unique(original.round(6),axis=0,return_index=True,return_inverse=True)
    v=original[first]
    faces=[]
    for refs,flags,uv in o['faces']:
        ids=[int(remap[i]) for i in refs];coords=v[ids]
        normal=np.sum(np.cross(coords,np.roll(coords,-1,axis=0)),axis=0)
        plane=np.delete(coords,int(np.argmax(abs(normal))),axis=1)
        edges=np.roll(plane,-1,axis=0)-plane
        turns=edges[:,0]*np.roll(edges,-1,axis=0)[:,1]-edges[:,1]*np.roll(edges,-1,axis=0)[:,0]
        concave=np.any(turns>1e-10) and np.any(turns< -1e-10)
        # A fan through the centroid of a concave window surround crosses its
        # aperture. Ear-clip first; never create out-of-polygon face points.
        if concave:
            for triangle in triangulate(ids,v):
                faces.append((triangle,flags,np.array([uv[ids.index(i)] for i in triangle])))
        else:faces.append((ids,flags,np.array(uv)))
    for _ in range(levels):
        nv=len(v);nf=len(faces);points=np.array([v[ids].mean(0) for ids,_,_ in faces])
        edges={};adj=[[] for _ in v];incident=[[] for _ in v];pinned=set()
        for fi,(ids,flags,_) in enumerate(faces):
            for i,j in zip(ids,ids[1:]+ids[:1]):
                edge=tuple(sorted((i,j)));edges.setdefault(edge,[]).append(fi)
                incident[i].append(fi)
            if not flags&0x10:pinned.update(ids)
        keys=list(edges);edge_points=[];edge_index={edge:nv+nf+i for i,edge in enumerate(keys)}
        for i,j in keys:
            fs=edges[(i,j)];adj[i].append(j);adj[j].append(i)
            hard=len(fs)!=2 or any(not faces[f][1]&0x10 for f in fs)
            if hard:
                pinned.update([i,j]);edge_points.append((v[i]+v[j])*.5)
            else:edge_points.append((v[i]+v[j]+points[fs[0]]+points[fs[1]])*.25)
        updated=v.copy()
        for i in range(nv):
            if i in pinned or not incident[i] or not adj[i]:continue
            # Hold extrema and the calibrated cylindrical width. This affects
            # very few vertices and avoids changing the measured dimensions.
            if np.any(np.isclose(v[i],bounds[0],atol=1e-7)) or np.any(np.isclose(v[i],bounds[1],atol=1e-7)):continue
            if -13 < v[i,2] < -10 and abs(abs(v[i,0])-(1.975 if bounds[0][2]>-19 else 1.88)) < .001:continue
            valence=len(adj[i]);F=points[incident[i]].mean(0);R=(v[adj[i]].mean(0)+v[i])*.5
            updated[i]=(F+2*R+(valence-3)*v[i])/valence
        new_faces=[]
        for fi,(ids,flags,uv) in enumerate(faces):
            center_uv=uv.mean(0)
            # Advect face-varying UVs with the relocated control vertices. A
            # tangent-plane fit avoids stretching windows/lettering when the
            # source has unevenly spaced stations. Discard the curvature axis.
            jacobian=np.linalg.lstsq(v[ids]-v[ids].mean(0),uv-center_uv,rcond=.08)[0]
            for j,i in enumerate(ids):
                nxt=ids[(j+1)%len(ids)];prev=ids[j-1]
                new_faces.append(([i,edge_index[tuple(sorted((i,nxt)))],nv+fi,edge_index[tuple(sorted((prev,i)))]],flags,
                    np.array([uv[j]+(updated[i]-v[i])@jacobian,
                        (uv[j]+uv[(j+1)%len(ids)])*.5+(edge_points[edge_index[tuple(sorted((i,nxt)))]-nv-nf]-(v[i]+v[nxt])*.5)@jacobian,
                        center_uv,
                        (uv[j-1]+uv[j])*.5+(edge_points[edge_index[tuple(sorted((prev,i)))]-nv-nf]-(v[prev]+v[i])*.5)@jacobian])))
        v=np.clip(np.concatenate([updated,points,np.array(edge_points)]),*bounds);faces=new_faces
    o['vertices']=v;o['faces']=faces


def add_glazing_rebates(objects,a):
    """Model the glass seal separately from the painted frame, using real outlines."""
    targets=[o for o in objects if (o['name']=='Windsheild' or o['name'].startswith('WindowGlass'))]
    additions=[]
    for o in targets:
        old=o['vertices'];glass=[];gf=[];seal=[];sf=[]
        for ids,flags,uv in o['faces']:
            ring=old[ids];center=ring.mean(0)
            # 12 mm rubber seal inside the source aperture; no enlarged holes.
            radius=np.linalg.norm(ring-center,axis=1)
            inner=center+(ring-center)*(1-.012/np.maximum(radius,.05))[:,None]
            start=len(glass);glass.extend(inner);gf.append((list(range(start,len(glass))),0,[[.5,.5]]*len(ids)))
            for i in range(len(ids)):
                j=(i+1)%len(ids);start=len(seal);seal.extend([ring[i],ring[j],inner[j],inner[i]])
                sf.append((list(range(start,start+4)),0,[[.5,.5]]*4))
        o['vertices']=np.array(glass);o['faces']=gf
        additions.append({'name':'GlazingSeal','file':'generated-detail','texture':'','vertices':np.array(seal),'faces':sf})
    objects.extend(additions)

def mesh(objects,a):
    chunks=[];audit=[]
    for o in objects:
        v=o['vertices'];n=o['name'].lower();tri=[];smooth=[];uvs=[];polygon_normals=[]
        for refs,flags,uv in o['faces']:
            polygon=v[refs];pn=np.sum(np.cross(polygon,np.roll(polygon,-1,axis=0)),axis=0);pn/=max(np.linalg.norm(pn),1e-12)
            for t in triangulate(refs,v):
                tri.append(t);smooth.append(bool(flags&0x10));uvs.append([uv[refs.index(i)] for i in t])
                polygon_normals.append(pn)
        if not tri: continue
        tri=np.array(tri,dtype=np.int32);p=v[tri];norm=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(norm,axis=1);valid=area>1e-10
        tri=tri[valid];p=p[valid];norm=norm[valid];smooth=np.array(smooth)[valid];uvs=np.array(uvs)[valid];area=area[valid];unit=norm/area[:,None]
        # Weld coincident source vertices for normals. UV seams stay separate.
        _,weld=np.unique(v.round(6),axis=0,return_inverse=True)
        angles=np.zeros(tri.shape)
        for j in range(3):
            e0=p[:,(j+1)%3]-p[:,j];e1=p[:,(j+2)%3]-p[:,j]
            cosine=np.sum(e0*e1,axis=1)/np.maximum(np.linalg.norm(e0,axis=1)*np.linalg.norm(e1,axis=1),1e-12)
            angle=np.arccos(np.clip(cosine,-1,1))
            angles[:,j]=angle
        # AC3D crease angles separate a thin wing's upper/lower surfaces and
        # sharp panel edges. Averaging every welded face cancels their normals
        # and produces apparent triangular holes despite continuous geometry.
        corner_weld=weld[tri].ravel();order=np.argsort(corner_weld,kind='stable')
        counts=np.bincount(corner_weld,minlength=weld.max()+1)
        starts=np.cumsum(counts)-counts
        current=np.repeat(unit,3,axis=0);normals=np.zeros_like(current)
        threshold=np.cos(np.deg2rad(min(89.9,o.get('crease',45.0))))
        for rank in range(int(counts.max())):
            active=np.flatnonzero((counts[corner_weld]>rank)&np.repeat(smooth,3))
            other=order[starts[corner_weld[active]]+rank]
            face=other//3
            allowed=(np.einsum('ij,ij->i',current[active],unit[face])>=threshold)&smooth[face]
            active=active[allowed];other=other[allowed];face=face[allowed]
            normals[active]+=unit[face]*angles.ravel()[other,None]
        normals=normals.reshape(-1,3,3)
        normals/=np.maximum(np.linalg.norm(normals,axis=2)[:,:,None],1e-10)
        normals=np.where(smooth[:,None,None],normals,unit[:,None,:])
        # Coincident opposite skins can cancel at a welded source seam. Fall
        # back to that face normal instead of sending normalize(0) to Metal.
        cancelled=np.linalg.norm(normals,axis=2)<.5
        normals=np.where(cancelled[:,:,None],unit[:,None,:],normals)
        color=[.38,.47,.54,0]
        if any(x in n for x in ['wind','fan','duct','exhaust','tailpipe','engcore','inner']):color=[.035,.065,.085,0]
        if any(x in n for x in ['rudder','vstab']):color=[.28,.38,.46,1]
        if any(x in n for x in ['slat','spoiler','elevator','aileron','flap']):color=[.29,.39,.47,0]
        if 'light' in n or 'navglass' in n: color=[.16,.22,.27,0]
        # Semantic parts for paint, roughness, rotating fans and light response.
        part=2
        if n in ['fuselage'] or n.startswith(('door','dorr','mlggeardoor','nlgaftdoor','nlgforewarddoor')):part=1
        if n in ['rudder','vstab','vstable']:part=3
        if any(x in n for x in ['eng','reverser','tailpipe','duct','spinner']):part=4
        if n=='windsheild' or n.startswith('windowglass') or n=='rearwindows.ext':part=5
        if n=='windows':part=7
        if n=='glazingseal' or 'wiper' in n:part=9
        if n in ['engnose','engnose.003']:part=8
        if n.startswith(('slat','ible','oble')):part=12
        if 'fan' in n and 'case' not in n:part=6
        part=o.get('part',part)
        if n=='rearwindows.ext':part=13
        if part==5 and o.get('file')=='flightdeck.ac':normals=np.repeat(np.array(polygon_normals)[valid,None,:],3,axis=1)
        tex={'Fuse-Main.png':1,'engine-CFM56.png':2,'Static-Elements.png':3,'737-800.png':4}.get(o['texture'],0)
        tex=o.get('textureIndex',tex)
        row=np.zeros((len(p)*3,16),dtype='<f4');row[:,:3]=p.reshape(-1,3);row[:,3]=1;row[:,4:7]=normals.reshape(-1,3);row[:,8:12]=color
        row[:,12:14]=uvs.reshape(-1,2);row[:,14]=tex;row[:,15]=part
        if part==6:
            side=np.sign(v[:,0].mean());row[:,11]=side
            # Keep native fan/spinner artwork. Procedural spinner coordinates
            # are derived from the engine axis in the vertex shader instead.
        if a=='airbus' and n.startswith('enginecfm'):
            # The intake is a separate polished alloy region, including the
            # rolled inner lip. Classify complete triangles, never interpolate IDs.
            lip=p[:,:,2].mean(1)<-7.20
            row[np.repeat(lip,3),15]=8
        chunks.append(row);audit.append({'name':o['name'],'source':o.get('source',o['file']),'triangles':len(p),'min':v.min(0).tolist(),'max':v.max(0).tolist()})
    return np.concatenate(chunks),audit

def seal_cockpit_glazing(objects,a):
    if a!='boeing':return 0
    from collections import Counter,defaultdict
    frame=next(o for o in objects if o['name']=='windows')
    vertices,original,remap=np.unique(frame['vertices'].round(6),axis=0,return_index=True,return_inverse=True)
    vertices=frame['vertices'][original]
    edges=Counter()
    for refs,_,_ in frame['faces']:
        refs=[int(remap[i]) for i in refs]
        for i,j in zip(refs,refs[1:]+refs[:1]):edges[tuple(sorted((i,j)))]+=1
    adjacency=defaultdict(set)
    for (i,j),count in edges.items():
        if count==1:adjacency[i].add(j);adjacency[j].add(i)
    loops=[];remaining=set(adjacency)
    while remaining:
        start=min(remaining);loop=[start];previous=None;current=start
        while True:
            candidates=adjacency[current]-({previous} if previous is not None else set())
            assert candidates,'Open glazing boundary'
            nxt=min(candidates)
            if nxt==start:break
            assert nxt not in loop,'Non-simple glazing boundary'
            loop.append(nxt);previous,current=current,nxt
        remaining.difference_update(loop);loops.append(loop)
    # The largest perimeter is the frame's outer seam. Its six interior loops
    # are the actual panes, omitted from this upstream exterior-only AC file.
    perimeter=lambda loop:sum(np.linalg.norm(vertices[i]-vertices[j]) for i,j in zip(loop,loop[1:]+loop[:1]))
    outer=max(loops,key=perimeter);panes=[loop for loop in loops if loop is not outer]
    assert len(panes)==6,('Unexpected cockpit glazing topology',len(panes))
    for i,loop in enumerate(panes):
        v=vertices[loop]
        objects.append({'name':f'WindowGlass{i+1}','file':'generated-cockpit-glazing','texture':'','vertices':v,
                        'faces':[(list(range(len(v))),0,[[.5,.5]]*len(v))]})
    return len(panes)

def build_bvh(data,path):
    triangles=data[:,:3].reshape(-1,3,3);centers=triangles.mean(1)
    low=triangles.min(1);high=triangles.max(1);nodes=[];order=[]
    def node(ids):
        index=len(nodes);nodes.append(None);lo=low[ids].min(0);hi=high[ids].max(0)
        if len(ids)<=8:
            left=len(order);order.extend(ids.tolist());right=0;count=len(ids)
        else:
            axis=int(np.argmax(np.ptp(centers[ids],axis=0)));ids=ids[np.argsort(centers[ids,axis],kind='stable')];middle=len(ids)//2
            left=node(ids[:middle]);right=node(ids[middle:]);count=0
        nodes[index]=struct.pack('<6f4I',*lo,*hi,left,right,count,0);return index
    node(np.arange(len(triangles)))
    path.write_bytes(struct.pack('<4s3I',b'WBVH',len(nodes),len(triangles),1)+b''.join(nodes)+triangles[order].astype('<f4').tobytes())

if __name__ == '__main__':
    wanted=sys.argv[1:]
    reports=json.loads((DEST/'audit.json').read_text()) if wanted and (DEST/'audit.json').exists() else {}
    for a,folder,names in [('airbus','A320',['A320-216.ac','CFM56.ac']),('boeing','737',['737-800.ac','LWing.ac','RWing.ac','HorzStab.ac','VertStab.ac','winglet.ac'])]:
        if wanted and a not in wanted:continue
        objs=[o for name in names for o in read_ac(ROOT/'ThirdParty'/folder/name) if selected(o,a)]
        if a=='boeing':upgrade_737_details(objs)
        dims=calibrate(objs,a);panes=seal_cockpit_glazing(objs,a);add_glazing_rebates(objs,a)
        if a=='boeing':add_737_compressor_backstops(objs)
        for o in objs:
            n=o['name'].lower()
            levels=3 if n=='fuselage' else (2 if n.startswith('enginecfm') else (1 if any(k in n for k in ['engnose','engfancase','reverser']) or n.startswith(('door','dorr')) else 0))
            if levels:subdivide_surface(o,levels)
        data,audit=mesh(objs,a)
        assert np.isfinite(data).all() and np.all(np.abs(np.linalg.norm(data[:,4:7],axis=1)-1)<.02), "Invalid mesh normal"
        path=DEST/(a+'.mesh');path.write_bytes(data.tobytes());build_bvh(data,DEST/(a+'.bvh'))
        points=data[:,:3];h=np.concatenate([o['vertices'] for o in objs if o['name'] in ['Hstabs','ElevatorL','ElevatorR'] or o['file']=='HorzStab.ac'])
        f=next(o for o in objs if o['name'] in ['Fuselage','fuselage']);fv=points[(data[:,15]==1)&(points[:,2]>-13)&(points[:,2]<-10)]
        actual=[float(np.ptp(points[:,2])),float(np.ptp(points[:,0])),float(np.ptp(h[:,0])),float(np.ptp(fv[:,0]))]
        checks=[{'dimension':k,'targetMetres':t,'meshMetres':round(x,6),'errorMetres':round(abs(x-t),6)} for k,t,x in zip(['overallLength','wingspan','horizontalTailSpan','forebodyWidth'],dims,actual)]
        # A model is released only if the four measured constraints pass at 5 mm.
        assert all(c['errorMetres']<.005 for c in checks),checks
        reports[a]={'units':'metres','addedCockpitPanes':panes,'vertices':len(data),'triangles':len(data)//3,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'dimensions':checks,'objects':audit}
        print(a,len(data)//3,'triangles',checks)
    (DEST/'audit.json').write_text(json.dumps(reports,indent=2))
