#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]];float2 uv; };
struct Uniforms { float2 size;float time;float environment;float4 options;float4 motion;float4 backgrounds;float4 weather;float4 lightning; };
struct LampData { float4 geometry;float4 color;float4 info; };
float hash21(float2 p);
struct FlowUniforms { float4x4 mvp;float4 viewport;float4 options;float4 field;float4 silhouette;float4 silhouetteRadius;float4x4 aircraftTransform;float4 flowBounds; };
struct FlowSegment { float4 start;float4 end; };
struct FlowOut { float4 clip [[position]];float side;float distance;float speed;float id [[flat]]; };
float3 flowWorldPosition(float3 p,constant FlowUniforms &u) {
    float3 outside=abs(p)-u.flowBounds.xyz;
    float influence=1-smoothstep(0.0,u.flowBounds.w,max(outside.x,max(outside.y,outside.z)));
    return mix(p,(u.aircraftTransform*float4(p,1)).xyz,influence);
}
vertex FlowOut flowVertex(uint id [[vertex_id]],uint instance [[instance_id]],device const FlowSegment *lines [[buffer(0)]],constant FlowUniforms &u [[buffer(1)]]) {
    constexpr float2 corner[6]={float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
    FlowSegment line=lines[instance];float2 c=corner[id];
    float4 a=u.mvp*float4(flowWorldPosition(line.start.xyz,u),1),b=u.mvp*float4(flowWorldPosition(line.end.xyz,u),1);
    float2 delta=(b.xy/max(.01,b.w)-a.xy/max(.01,a.w))*u.viewport.xy;
    float2 normal=float2(-delta.y,delta.x)*rsqrt(max(dot(delta,delta),.00001));
    float4 clip=mix(a,b,c.x);
    clip.xy+=normal*c.y*u.viewport.z*2/u.viewport.xy*clip.w;
    return {clip,c.y,mix(line.start.w,line.end.w,c.x)/u.field.x,length(line.end.xyz-line.start.xyz)/(u.field.x*u.field.y),float(instance/uint(u.viewport.w))};
}
fragment float4 flowFragment(FlowOut in [[stage_in]],constant FlowUniforms &u [[buffer(1)]]) {
    float edge=1-smoothstep(.35,1.0,abs(in.side));
    float fade=smoothstep(0.0,5.0,in.distance)*(1-smoothstep(116.0,128.0,in.distance));
    float phase=fract(in.distance*.055-u.options.x*.88*clamp(u.options.z,.35,1.75)+in.id*.173);
    float packet=exp(-pow((phase-.60)*11,2));
    float crest=exp(-pow((phase-.66)*34,2));
    float day=u.options.y*.5;
    float acceleration=smoothstep(1.015,1.22,in.speed);
    float3 color=mix(mix(float3(.10,.55,.85),float3(.015,.22,.34),day),mix(float3(.30,.92,.79),float3(.025,.42,.40),day),acceleration);
    color=mix(color,mix(float3(.55,.92,1),float3(.02,.24,.34),day),crest*.7);
    // Depth testing removes paths behind the model. Reduce the visual weight
    // of legitimate foreground paths over the fuselage so it never looks X-rayed.
    float2 axis=u.silhouette.zw-u.silhouette.xy,relative=in.clip.xy-u.silhouette.xy;
    float distance=length(relative-axis*clamp(dot(relative,axis)/max(.001,dot(axis,axis)),0.0,1.0));
    float clarity=mix(.10,1.0,smoothstep(u.silhouetteRadius.x*.75,u.silhouetteRadius.x*1.65,distance));
    float alpha=edge*fade*(.012+packet*.22+crest*.10)*u.options.w*clarity;
    return float4(color,alpha);
}
struct MeshVertex { float4 position;float4 normal;float4 color;float4 uv; };
struct MeshUniforms {
    float4x4 mvp;float4 eye;float4 options;float4 conditions;float4 sunlight;float4 engineGeometry;float4 logoSource;float4 logoTarget;
    float4x4 shadow0;float4x4 shadow1;float4x4 sun;float4 weather;float4 surface;float4 lightning;
};
struct MeshOut { float4 clip [[position]];float3 position;float3 normal;float4 color;float4 uv;float3 barycentric;float2 rotor; };
vertex MeshOut meshVertex(uint id [[vertex_id]],device const MeshVertex *vertices [[buffer(0)]],constant MeshUniforms &u [[buffer(1)]]) {
    MeshVertex v = vertices[id];
    float2 rotor=v.position.xy-float2(v.color.w*u.engineGeometry.x,u.engineGeometry.y);
    if (v.uv.w == 6) {
        float side = v.color.w;
        float2 center = float2(side*u.engineGeometry.x,u.engineGeometry.y);
        float angle = u.conditions.x*3.8; // perceptual rotation, not a claimed engine RPM
        float2x2 r = float2x2(cos(angle),sin(angle),-sin(angle),cos(angle));
        v.position.xy = center+r*(v.position.xy-center);v.normal.xy = r*v.normal.xy;
    }
    float3 bary = float3(0);bary[id%3] = 1;
    return {u.mvp*v.position,v.position.xyz,v.normal.xyz,v.color,v.uv,bary,rotor};
}
vertex float4 shadowVertex(uint id [[vertex_id]],device const MeshVertex *vertices [[buffer(0)]],constant float4x4 &matrix [[buffer(1)]]) {
    return matrix*vertices[id].position;
}
float shadowVisibility(depth2d<float> map,float4x4 matrix,float3 point,float3 normal) {
    float4 clip = matrix*float4(point+normal*.015,1);
    float3 p = clip.xyz/clip.w;
    float2 uv = p.xy*float2(.5,-.5)+.5;
    if (clip.w<=0 || any(uv<0) || any(uv>1) || p.z>=1 || p.z<0) return 1;
    constexpr sampler cmp(coord::normalized,filter::linear,address::clamp_to_edge,compare_func::less_equal);
    float2 texel = 1.0/float2(map.get_width(),map.get_height());
    float value=0;
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) value+=map.sample_compare(cmp,uv+float2(x,y)*texel,p.z-.00035);
    return value/9;
}
float3 brdf(float3 base,float rough,float metallic,float3 n,float3 v,float3 l) {
    float nl=max(dot(n,l),0.0),nv=max(dot(n,v),.001);
    float3 h=normalize(v+l);float nh=max(dot(n,h),0.0),vh=max(dot(v,h),0.0);
    float a=rough*rough,a2=a*a,d=a2/(M_PI_F*pow(nh*nh*(a2-1)+1,2));
    float k=pow(rough+1,2)/8,g=(nv/(nv*(1-k)+k))*(nl/(nl*(1-k)+k));
    float3 f0=mix(float3(.04),base,metallic);float3 f=f0+(1-f0)*pow(1-vh,5);
    return (base*(1-f)*(1-metallic)/M_PI_F+d*g*f/(4*nv*max(nl,.001)))*nl;
}
fragment float4 meshFragment(MeshOut in [[stage_in]],constant MeshUniforms &u [[buffer(1)]],
    texture2d<float> china [[texture(0)]],texture2d<float> chinaAirbus [[texture(1)]],texture2d<float> engine [[texture(2)]],
    depth2d<float> tailL [[texture(3)]],depth2d<float> tailR [[texture(4)]],depth2d<float> sun [[texture(5)]],texture2d<float> skinNormal [[texture(6)]],texture2d<float> engineNormal [[texture(7)]],array<texture2d<float>,16> atlases [[texture(8)]],texture2d<float> windowMask [[texture(24)]],sampler tex [[sampler(0)]]) {
    float3 p=in.position,n=normalize(in.normal),v=normalize(u.eye.xyz-p);
    if (dot(n,v)<0) n=-n; // the upstream exterior includes intentionally two-sided skins
    int part=int(in.uv.w+.1),tid=int(in.uv.z+.1);bool airbus=u.options.w<.5;
    // Original model-space UV normal atlases add real upstream seam/rivet
    // detail. Decode as linear data. AC v was flipped for top-left textures,
    // so tangent-space Y must flip as well; geometry derivatives supply T/B.
    float3 dx=dfdx(p),dy=dfdy(p);float2 tx=dfdx(in.uv.xy),ty=dfdy(in.uv.xy);
    float det=tx.x*ty.y-tx.y*ty.x;
    if (airbus && (tid==1 || tid==2) && part!=5 && part!=6 && part!=8 && part!=9 && abs(det)>1e-12) {
        float3 mapped=(tid==1 ? skinNormal.sample(tex,in.uv.xy).xyz : engineNormal.sample(tex,in.uv.xy).xyz)*2-1;
        mapped.xy*=float2(.45,-.45);mapped=normalize(mapped);
        float3 tangent=(dx*ty.y-dy*tx.y)/det,bitangent=(dy*tx.x-dx*ty.x)/det;
        tangent=normalize(tangent-n*dot(n,tangent));
        bitangent=normalize(cross(n,tangent))*sign(dot(cross(n,tangent),bitangent));
        n=normalize(tangent*mapped.x+bitangent*mapped.y+n*mapped.z);
    }
    float3 base=float3(.76,.78,.79);float rough=.26,metallic=0;
    if (part==2) {base=float3(.53,.56,.59);rough=.37;}
    if (part==4) {base=float3(.72);rough=.26;}
    if (part==5 || part==6 || (part==4 && in.color.r<.1)) {base=float3(.025,.035,.042);rough=part==5 ? .13 : .45;}
    if (u.options.z>.5) {
        if (tid>=10 && tid<26) {
            float2 uv=in.uv.xy;
            // The original CXA side projection mirrors Latin text, but its
            // Chinese wordmark was left unmirrored. Correct this UV island only.
            if (u.engineGeometry.w>.5 && tid==13 && part==1 && p.x>0 && uv.x>.223 && uv.x<.298 && uv.y>.377 && uv.y<.399) uv.x=.521-uv.x;
            base=atlases[tid-10].sample(tex,uv).rgb;
        }
        else if (!airbus && tid==4) {
            base=china.sample(tex,in.uv.xy).rgb;
            // This livery contains a painted windshield below the actual 3D
            // cockpit opening. Use painted metal there; the six panes have
            // their own closed geometry and glass material.
            if (part==1 && p.z < -16 && p.y > .25) {
                float high=max(base.r,max(base.g,base.b)),low=min(base.r,min(base.g,base.b));
                float oldGlazing=(1-smoothstep(.10,.19,high))*(1-smoothstep(.012,.035,high-low));
                base=mix(base,float3(.79),oldGlazing);
            }
        } else if (airbus) {
            // Native A320 UV islands contain independently painted port and
            // starboard sides, doors, windows, wing surfaces and tail markings.
            if (tid==1) base=chinaAirbus.sample(tex,in.uv.xy).rgb;
            if (tid==2 && part!=6) {
                float3 source=engine.sample(tex,in.uv.xy).rgb;
                if (u.options.z>1.5) base=source;
                else base*=mix(.12,1.0,smoothstep(.025,.19,max(source.r,max(source.g,source.b))));
            }
        }
    }
    if (part==7) {base=float3(.67,.70,.71);rough=.25;}
    if (part==9) {base=float3(.021,.025,.028);rough=.65;}
    if ((part==8 && !airbus) || part==12) {base=float3(.65,.69,.72);rough=part==8 ? .19 : .30;metallic=.92;}
    if (airbus && tid==2 && (part==4 || part==8)) {
        // A continuous inlet station avoids a sawtooth paint/metal boundary
        // from classifying whole triangles on dark or brightly painted cowls.
        float lip=1-smoothstep(-7.22,-7.18,p.z);
        base=mix(base,float3(.65,.69,.72),lip);rough=mix(rough,.19,lip);metallic=.92*lip;
    }
    if (part==5 || part==13) {base=float3(.012,.023,.032);rough=.095;}
    if (part==6) {
        base=float3(.16,.185,.21);rough=.36;metallic=.8;
        bool nativeFan=tid>=10 && tid<26;
        if (nativeFan) { base=atlases[tid-10].sample(tex,in.uv.xy).rgb;metallic=.45; }
        else if (airbus && tid==2) { base=engine.sample(tex,in.uv.xy).rgb;nativeFan=true;metallic=.45; }
        float2 q=in.rotor;float radius=length(q);
        // Spinner markings are surface coordinates and rotate with the mesh.
        if (!nativeFan && radius<.235) {
            float turn=atan2(q.y,q.x)+radius*27;
            float aa=max(fwidth(turn),.02);
            float spiral=(1-smoothstep(.20-aa,.20+aa,abs(sin(turn*.5))))*smoothstep(.03,.07,radius);
            base=mix(float3(.065,.078,.09),float3(.72),spiral);metallic=.25;rough=.30;
        }
    }
    float daylight=clamp(u.conditions.y*.5,0.0,1.0);
    float3 ambient=mix(float3(.007,.012,.022),float3(.31,.36,.43),daylight)*(1-.30*u.weather.x-.24*u.weather.w);
    float hemi=.40+.60*clamp(n.y*.5+.5,0.0,1.0);
    float studio=u.engineGeometry.z;
    float cabin=part==13 ? 1.0 : 0.0;
    if (part==1 && u.surface.y>0.5) cabin=windowMask.sample(tex,in.uv.xy).r*(1-smoothstep(.20,.46,max(base.r,max(base.g,base.b))));
    rough=mix(rough,max(.12,rough*.55),u.weather.y);
    ambient=mix(ambient,mix(float3(.016,.022,.030),float3(.23,.25,.28),daylight),studio);
    float3 color=base*ambient*hemi;
    float3 sunDirection=normalize(u.sunlight.xyz);
    float direct=u.sunlight.w>0 ? smoothstep(-.0145,.06,u.conditions.w) : smoothstep(0.0,.8,u.conditions.y);
    float warmth=exp(-pow((u.conditions.y-1.0)*1.9,2));
    float3 sunColor=mix(float3(2.15,2.0,1.74),float3(1.8,.69,.25),warmth)*direct*(1-u.conditions.z)*(1-.94*u.weather.x);
    // These terms are exactly zero outside their active lighting conditions.
    // Preserve all samples/BRDFs when they contribute, including transitions.
    if (direct>0 && u.conditions.z<1 && dot(n,sunDirection)>0) {
        float visibility=shadowVisibility(sun,u.sun,p,n);
        color+=brdf(base,rough,metallic,n,v,sunDirection)*sunColor*visibility*(1-studio*.65);
    }
    float studioPower=mix(.16,1.0,daylight)*studio;
    if (studioPower>0) {
        color+=brdf(base,max(rough,.22),metallic,n,v,normalize(float3(-.6,1,-.4)))*float3(2.4,2.30,2.14)*studioPower;
        color+=brdf(base,max(rough,.28),metallic,n,v,normalize(float3(.8,.55,.3)))*float3(.80,1.05,1.36)*studioPower;
        color+=brdf(base,max(rough,.32),metallic,n,v,normalize(float3(-.2,.5,1)))*float3(.85,.95,1.15)*studioPower;
    }
    // Two physical point spotlights on the horizontal stabilizer, aimed at the
    // fin. Lambert/BRDF cosine, inverse-square falloff and depth-map occlusion.
    if (u.options.y>0) {
        float3 target=u.logoTarget.xyz;
        for (int i=0;i<2;i++) {
            float3 source=u.logoSource.xyz;source.x=abs(source.x)*(i==0 ? -1 : 1);
            float3 delta=source-p;float d2=dot(delta,delta),cone=smoothstep(.61,.86,dot(normalize(p-source),normalize(target-source)));
            if (cone>0 && dot(n,delta)>0) {
                float vis=i==0 ? shadowVisibility(tailL,u.shadow0,p,n) : shadowVisibility(tailR,u.shadow1,p,n);
                color+=brdf(base,.45,metallic,n,v,normalize(delta))*float3(1,.94,.83)*(85/max(d2,.16))*cone*vis*exp2(-daylight*6);
            }
        }
    }
    // Analytic distant sky reflection: direction-dependent specular response
    // distinguishes painted skins, dielectric glazing and polished intake alloy.
    // This is an environment approximation, not screen-space ray tracing.
    float3 reflection=reflect(-v,n);
    float horizon=exp(-pow(reflection.y*3.2,2));
    float3 sky=mix(float3(.10,.15,.19),float3(.33,.53,.78),smoothstep(-.2,.6,reflection.y));
    sky=mix(sky,float3(.78,.82,.85),horizon*.65);
    if (studio>0) {
        float box1=pow(max(0.0,dot(reflection,normalize(float3(-.6,1,-.4)))),18.0);
        float box2=pow(max(0.0,dot(reflection,normalize(float3(.8,.55,.3)))),28.0);
        sky=mix(sky,float3(.13,.16,.20)+float3(2.2,2.15,2.05)*box1+float3(1.0,1.20,1.5)*box2,studio);
    }
    float nv=max(dot(n,v),0.0);
    float3 f0=mix(float3(part==5 ? .065 : .04),base,metallic);
    float3 fresnel=f0+(1-f0)*pow(1-nv,5);
    float cavity=(part==6 || (part==4 && in.color.r<.1)) ? .22 : 1;
    color+=sky*fresnel*(1-rough*.7)*daylight*cavity;
    // Fine joints on the actual cylindrical intake; derivative AA keeps them
    // stable when zooming, without pretending that a larger atlas adds detail.
    if (part==8) {
        float2 axis=p.xy-float2(sign(p.x)*u.engineGeometry.x,u.engineGeometry.y);
        float angle=atan2(axis.y,axis.x);
        float seam=abs(sin(angle*4));float aa=max(fwidth(seam),.001);
        color*=1-.16*(1-smoothstep(.004,.004+aa,seam));
    }
    // Warm cabin emission sits on depth-tested glazing/painted-window masks.
    // Cockpit panes remain dark; no billboard can shine through the airframe.
    float rowVariation=.72+.28*fract(sin(floor(p.z*1.6)*71.7)*437.2);
    color+=float3(.54,.31,.12)*cabin*u.surface.x*(1-smoothstep(.13,.72,daylight))*rowVariation;

    float fog=1-exp(-length(u.eye.xyz-p)*u.weather.z*.014);
    color=mix(color,mix(float3(.014,.022,.032),float3(.34,.39,.43),daylight),fog);
    color=color/(1+color*.28); // fixed scene exposure; the EDR emitters bypass it
    if (u.options.x>1.5) return float4(.80,.24,.055,1);
    if (u.options.x>0) {
        float3 edge=smoothstep(float3(0),fwidth(in.barycentric),in.barycentric);
        color=mix(float3(.12,.24,.29),color*.5,min(edge.x,min(edge.y,edge.z)));
    }
    float3 reflectionFlash=0;
    if (u.lightning.x>0) {
        float sourceX=.38+.46*hash21(float2(u.lightning.z,9));
        float3 cameraDirection=normalize(u.eye.xyz);
        float3 right=normalize(cross(float3(0,1,0),cameraDirection));
        float3 flashDirection=normalize(float3(0,.9,0)-cameraDirection*.45+right*(sourceX-.5)*1.6);
        // A distant flash lights the same physical materials as the sun/studio,
        // with a small diffuse cloud-scattering fill rather than flat whitening.
        reflectionFlash=(brdf(base,rough,metallic,n,v,flashDirection)*float3(1.15,1.30,1.55)
            +base*float3(.035,.045,.065))*u.lightning.x*min(2.0,u.lightning.y);
    }
    return float4(min(clamp(color,0.0,.95)+reflectionFlash,float3(u.lightning.y)),1);
}
vertex VertexOut sceneVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2);return {float4(p*float2(2,-2)+float2(-1,1),0,1),p};
}
vertex VertexOut backgroundVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2);
    return {float4(p*float2(2,-2)+float2(-1,1),1,1),p};
}
float hash21(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
float noise(float2 p) {
    float2 i=floor(p),f=fract(p);f=f*f*(3-2*f);
    return mix(mix(hash21(i),hash21(i+float2(1,0)),f.x),mix(hash21(i+float2(0,1)),hash21(i+1),f.x),f.y);
}
// Linear, multiscale offsets make angular stepped channels rather than a
// smooth sine-wave ribbon. Repeated return strokes retain the same path.
float lightningJitter(float t,float seed,float frequency) {
    float cell=t*frequency,i=floor(cell);
    return mix(hash21(float2(i,seed)),hash21(float2(i+1,seed)),fract(cell))-.5;
}
float lightningPath(float t,float seed,float origin) {
    float lean=(hash21(float2(seed,27))-.5)*.18;
    return origin+lean*t+lightningJitter(t,seed+7,11)*.075
        +lightningJitter(t,seed+13,67)*.012;
}
float3 backgroundColor(float2 uv,constant Uniforms &u,int mode) {
    float2 q=(uv-.5)*float2(u.size.x/u.size.y,1);
    float day=u.environment*.5;
    float3 zenith=mix(float3(.002,.005,.014),float3(.09,.30,.57),day);
    float3 horizon=mix(float3(.012,.023,.042),float3(.58,.72,.83),day);
    float twilight=exp(-pow((u.environment-1)*2.2,2));
    zenith=mix(zenith,float3(.025,.043,.10),twilight);
    horizon=mix(horizon,float3(.34,.17,.12),twilight);
    float3 color=mix(zenith,horizon,smoothstep(.05,.95,uv.y));

    if (mode==0) {
        float travel=u.time*(.075+.065*u.motion.x);
        float2 cloud=float2(q.x*4.4+travel,pow(max(uv.y-.26,0.0),.65)*6.2+travel*.16);
        float f=noise(cloud)*.50+noise(cloud*2.05)*.26+noise(cloud*4.1)*.13+noise(cloud*8.2)*.065+noise(cloud*16.4)*.032;
        float bank=smoothstep(.37,.70,f)*smoothstep(.30,.70,uv.y);
        float3 cloudColor=mix(float3(.024,.036,.06),float3(.80,.84,.87),day);
        color=mix(color,cloudColor,bank*(.35+.65*u.weather.x));
        // A closer, faster cloud layer adds parallax without covering the model.
        float2 nearCloud=float2(q.x*3.0+travel*2.1,uv.y*4.2+travel*.30);
        float nearNoise=noise(nearCloud)*.64+noise(nearCloud*2.1)*.26+noise(nearCloud*4.2)*.10;
        float nearBank=smoothstep(.49,.72,nearNoise)*smoothstep(.45,.98,uv.y);
        color=mix(color,mix(float3(.042,.060,.083),float3(.91,.94,.96),day),nearBank*(.35+.50*u.weather.x));
    } else if (mode==1) {
        // Geometry-based streamlines are rendered in the depth-tested 3D pass.
        color=mix(float3(.005,.015,.026),float3(.48,.60,.67),day)*(1-.28*length(q));
        color+=mix(float3(.008,.020,.025),float3(.03,.04,.045),day)*exp(-dot(q,q)*2);
    } else if (mode==2) {
        // The star field is a deliberately dark scene, independent of local time.
        color=mix(float3(.0004,.0007,.0018),float3(.002,.004,.009),uv.y);
        float2 sky=uv*float2(250,160)+float2(u.time*.38,u.time*.045);
        float2 cell=floor(sky),local=fract(sky)-.5;
        float seed=hash21(cell);float stars=smoothstep(.986,1.0,seed)*exp(-dot(local,local)*48);
        stars*=.85+.15*sin(u.time*.9+seed*70);
        color+=stars*float3(.38,.44,.53);
        color+=exp(-pow((q.y+q.x*.15+.17)*7,2))*.006;
    } else {
        // Seamless cyclorama with broad softbox gradients. Pixel derivatives
        // keep the optional perspective floor guides stable on Retina displays.
        float sweep=smoothstep(.27,.95,uv.y);
        color=mix(mix(float3(.005,.008,.013),float3(.24,.29,.35),day),mix(float3(.022,.029,.040),float3(.65,.69,.73),day),sweep);
        float lightX=.10*sin(u.time*.10);
        float softbox=exp(-pow((q.x-lightX)*1.25,2)-pow((q.y+.26)*2.7,2));
        color+=mix(float3(.016,.024,.035),float3(.10,.105,.11),day)*softbox;
        color*=1-.14*smoothstep(.30,1.0,length(q));
        if (u.options.y>0) {
            float floor=smoothstep(.64,.90,uv.y),depth=max(.035,uv.y-.55);
            float2 plane=float2(q.x/depth,1/depth)*1.8;
            float2 width=max(fwidth(plane),float2(.001));
            float2 line=abs(fract(plane-.5)-.5)/width;
            float grid=1-smoothstep(.3,1.1,min(line.x,line.y));
            color+=mix(float3(.008,.011,.015),float3(.018,.022,.026),day)*grid*floor*.45;
        }
    }
    if (mode!=3) {
        float cloud=noise(q*2.7+float2(u.time*.013,0))*.65+noise(q*6.2+u.time*.009)*.35;
        float coverage=saturate(u.weather.x*(.80+.42*cloud));
        float3 overcast=mix(float3(.005,.010,.019),float3(.29,.34,.40),day)*(.65+cloud*.64);
        overcast*=1-.34*u.weather.y-.38*u.weather.w;
        color=mix(color,overcast,coverage);
        float veil=noise(q*1.8+u.time*.022)*.18+.82;
        color=mix(color,mix(float3(.027,.039,.052),float3(.53,.59,.63),day),u.weather.z*veil);
        if (u.lightning.x>0.001) {
            float seed=u.lightning.z;
            float x0=.38+.46*hash21(float2(seed,9));
            float top=.10+.13*hash21(float2(seed,17)),span=.43+.18*hash21(float2(seed,23));
            float t=(uv.y-top)/span,aspect=u.size.x/u.size.y;
            float path=lightningPath(t,seed,x0);
            float distance=abs(uv.x-path)*aspect;
            distance+=max(0.0,-t)*4+max(0.0,t-1)*4;
            float branchDistance=10;
            for (int branch=0;branch<4;branch++) {
                float salt=seed+float(branch)*19;
                float originT=.15+float(branch)*.17+hash21(float2(salt,31))*.07;
                float originX=lightningPath(originT,seed,x0);
                float local=t-originT,length=.13+hash21(float2(salt,37))*.18;
                float side=hash21(float2(salt,41))>.5 ? 1 : -1;
                float branchX=originX+side*local*(.35+hash21(float2(salt,43))*.45)
                    +lightningJitter(local,salt+47,83)*.014*smoothstep(0.0,.035,local);
                float d=abs(uv.x-branchX)*aspect+max(0.0,-local)*4+max(0.0,local-length)*4;
                branchDistance=min(branchDistance,d);
            }
            float width=max(.00022,.75/u.size.y);
            float core=1-smoothstep(width*.35,width*1.9,distance);
            core=max(core,(1-smoothstep(width*.25,width*1.25,branchDistance))*.56*u.lightning.w);
            float cloudDepth=noise(q*8.3+float2(seed*3,seed+4));
            float transmission=mix(.16,.92,smoothstep(.24,.72,cloudDepth));
            transmission*=smoothstep(0.0,.07,t)*(1-smoothstep(.87,1.0,t));
            float halo=exp(-distance*680)*.12+exp(-branchDistance*950)*.035*u.lightning.w;
            float2 glowPoint=(uv-float2(x0,top+.10))*float2(aspect,1);
            float bloom=exp(-dot(glowPoint,glowPoint)*17)*(.22+.40*cloudDepth)*(.55+.45*coverage);
            // Cloud scattering is broader and softer than the narrow white
            // discharge channel; near cloud layers veil parts of that channel.
            color+=float3(.57,.67,.86)*u.lightning.x*bloom;
            color+=float3(.90,.95,1)*u.lightning.x*transmission*(core*u.lightning.y+halo*min(3.0,u.lightning.y));
        }
    }
    return color;
}
fragment float4 backgroundFragment(VertexOut in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float3 color=0;
    for (int mode=0;mode<4;mode++) {
        if (u.backgrounds[mode]>.0001) color+=backgroundColor(in.uv,u,mode)*u.backgrounds[mode];
    }
    return float4(min(color,float3(u.lightning.y)),1);
}
fragment float4 copyFragment(VertexOut in [[stage_in]],texture2d<float> scene [[texture(0)]],texture2d<float> previous [[texture(1)]],constant float &blend [[buffer(0)]]) {
    constexpr sampler s(filter::nearest);
    float4 current=scene.sample(s,in.uv);
    if (blend>=1) return current;
    return mix(previous.sample(s,in.uv),current,blend);
}
struct FlareOut { float4 position [[position]];float2 pixel;uint lamp [[flat]]; };
vertex FlareOut flareVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant Uniforms &u [[buffer(0)]],constant LampData *lamps [[buffer(1)]]) {
    constexpr float2 corners[6]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
    LampData l=lamps[instance];float extent=l.geometry.w>0 ? l.geometry.z*26*u.options.w : 0;
    float2 pixel=l.geometry.xy+corners[id]*extent;
    return {float4(pixel/u.size*float2(2,-2)+float2(-1,1),0,1),pixel,instance};
}
float4 flareRadiance(FlareOut in,constant Uniforms &u,constant LampData *lamps) {
    LampData lamp=lamps[in.lamp];
    if (lamp.geometry.w<=0 || lamp.info.y>.5) discard_fragment();
    float2 delta=in.pixel-lamp.geometry.xy;float radius=lamp.geometry.z,d=length(delta);
    float core=1-smoothstep(radius*.65,radius,d);
    float halo=exp(-d*d/(2*pow(radius*2.8*u.options.w,2)))*.12;
    float wide=exp(-d*d/(2*pow(radius*8*u.options.w,2)))*.010;
    float star=exp(-abs(delta.y)/(radius*.17))*exp(-abs(delta.x)/(radius*7))*.09;
    star+=exp(-abs(delta.x)/(radius*.17))*exp(-abs(delta.y)/(radius*5))*.045;
    float shape=min(1.0,core+halo+wide+star*lamp.info.x);
    float peak=mix(1.0,u.options.z,lamp.info.x);
    return float4(lamp.color.rgb*lamp.geometry.w*peak*shape,1);
}
struct ColorAttachment { float4 color [[color(0),raster_order_group(0)]]; };
fragment ColorAttachment flareFragment(FlareOut in [[stage_in]],ColorAttachment previous,
    constant Uniforms &u [[buffer(0)]],constant LampData *lamps [[buffer(1)]]) {
    float4 light=flareRadiance(in,u,lamps);
    return {float4(min(previous.color.rgb+light.rgb,max(1.0,u.options.z)),1)};
}

// The iOS Simulator GPU does not expose framebuffer fetch. Accumulate the
// same positive radiance separately and apply the same bound after composition.
fragment float4 portableFlareFragment(FlareOut in [[stage_in]],constant Uniforms &u [[buffer(0)]],constant LampData *lamps [[buffer(1)]]) {
    return flareRadiance(in,u,lamps);
}
fragment float4 portableCopyFragment(VertexOut in [[stage_in]],texture2d<float> scene [[texture(0)]],texture2d<float> previous [[texture(1)]],texture2d<float> lights [[texture(2)]],constant float &blend [[buffer(0)]],constant float &peak [[buffer(1)]]) {
    constexpr sampler s(filter::nearest);
    float4 current=scene.sample(s,in.uv);
    float4 base=blend>=1 ? current : mix(previous.sample(s,in.uv),current,blend);
    float4 light=lights.sample(s,in.uv);
    return float4(light.a>0 ? min(base.rgb+light.rgb,max(1.0,peak)) : base.rgb,1);
}

struct RainOut { float4 clip [[position]];float2 uv;float fade; };
vertex RainOut rainVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant FlowUniforms &u [[buffer(1)]]) {
    constexpr float2 corner[6]={float2(0,-1),float2(1,-1),float2(0,1),float2(0,1),float2(1,-1),float2(1,1)};
    float seed=float(instance),extent=u.field.x;
    float3 p=float3(hash21(float2(seed,3)),hash21(float2(seed,7)),hash21(float2(seed,13)))*2-1;
    p.y=fract(p.y*.5+.5-u.options.x*.19)*2-1;
    p.z=fract(p.z*.5+.5+u.options.x*.23)*2-1;
    p*=extent;
    float3 end=p+float3(.06,-1.15,2.0);
    float4 a=u.mvp*float4(p,1),b=u.mvp*float4(end,1);
    if (a.w<=.1 || b.w<=.1) return {float4(2,2,2,1),0,0};
    float2 line=(b.xy/b.w-a.xy/a.w)*u.viewport.xy;
    float2 normal=normalize(float2(-line.y,line.x)+float2(.0001));
    float2 c=corner[id];float4 clip=mix(a,b,c.x);
    clip.xy+=normal*c.y*max(1.0,u.viewport.z*.45)/u.viewport.xy*clip.w;
    float distance=length(p-u.field.yzw);
    return {clip,float2(c.x,c.y),exp(-distance/extent)*u.options.z};
}
fragment float4 rainFragment(RainOut in [[stage_in]],constant FlowUniforms &u [[buffer(1)]]) {
    float alpha=(1-smoothstep(.25,1.0,abs(in.uv.y)))*sin(in.uv.x*M_PI_F)*in.fade*.68;
    return float4(mix(float3(.24,.36,.48),float3(.72,.82,.91),max(u.options.y*.5,u.options.w)),alpha);
}
