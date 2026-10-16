"""Pinned original atlases. No resampling; engine assembly follows source XML."""
from pathlib import Path
import json,urllib.request,urllib.parse,hashlib,xml.etree.ElementTree as E,concurrent.futures,time,re,threading
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];RESEARCH=ROOT/'ThirdParty/WidebodyLiveries/Rebuild';DEST=ROOT/'Sources/Winglight/Resources/Liveries';LEGAL=ROOT/'ThirdParty/WidebodyLiveries';LEGAL.mkdir(exist_ok=True)
REPOS={'787':'IskenderWang/787-family','330':'JMaverick16/Airbus_A330','350':'FGMEMBERS/A350XWB','777':'franck-vmd/Boeing-777-Flightgear','extra':'sriemmanuel787/FG-Liveries'}
TREES={k:json.loads((RESEARCH/(r.replace('/','_')+'-tree.json')).read_text()) for k,r in REPOS.items()}
PATHS={k:{i['path'].lower():i['path'] for i in t['tree'] if i['type']=='blob'}for k,t in TREES.items()};LOCKS={};LOCK=threading.Lock()
NAMES={}
for row in '''CCA|中国国际航空|中国
CES|中国东方航空|中国
CSN|中国南方航空|中国
CXA|厦门航空|中国
CHH|海南航空|中国
HDA|港龙航空|中国
CRK|香港航空|中国
CPA|国泰航空|中国
CAL|中华航空|中国
EVA|长荣航空|中国
AAL|美国航空|美洲
ACA|加拿大航空|美洲
DAL|达美航空|美洲
UAL|美国联合航空|美洲
LAN|LATAM 智利航空|美洲
TAM|LATAM 巴西航空|美洲
AVA|哥伦比亚航空|美洲
HAL|夏威夷航空|美洲
ARG|阿根廷航空|美洲
AZU|巴西蓝色航空|美洲
FWI|加勒比航空|美洲
AFR|法国航空|欧洲
BAW|英国航空|欧洲
DLH|汉莎航空|欧洲
KLM|荷兰皇家航空|欧洲
FIN|芬兰航空|欧洲
SWR|瑞士国际航空|欧洲
SAS|北欧航空|欧洲
LOT|波兰航空|欧洲
NRS|挪威航空|欧洲
VIR|维珍大西洋航空|欧洲
TOM|途易航空|欧洲
THY|土耳其航空|欧洲
AEA|欧罗巴航空|欧洲
AFL|俄罗斯航空|欧洲
SDM|俄罗斯航空 Rossiya|欧洲
EIN|爱尔兰航空|欧洲
IBE|伊比利亚航空|欧洲
TAP|葡萄牙航空|欧洲
BEL|布鲁塞尔航空|欧洲
AUA|奥地利航空|欧洲
EDW|雪绒花航空|欧洲
EWG|欧洲之翼|欧洲
RZO|亚速尔航空|欧洲
GRL|格陵兰航空|欧洲
ANA|全日空|亚洲与中东
JAL|日本航空|亚洲与中东
AIC|印度航空|亚洲与中东
BBC|孟加拉国航空|亚洲与中东
SIA|新加坡航空|亚洲与中东
TGW|酷航|亚洲与中东
ETD|阿提哈德航空|亚洲与中东
UAE|阿联酋航空|亚洲与中东
QTR|卡塔尔航空|亚洲与中东
SVA|沙特阿拉伯航空|亚洲与中东
KAL|大韩航空|亚洲与中东
AAR|韩亚航空|亚洲与中东
MAS|马来西亚航空|亚洲与中东
GIA|印度尼西亚鹰航|亚洲与中东
THA|泰国国际航空|亚洲与中东
HVN|越南航空|亚洲与中东
ALK|斯里兰卡航空|亚洲与中东
CEB|宿务太平洋航空|亚洲与中东
XAX|亚洲航空长途|亚洲与中东
OMA|阿曼航空|亚洲与中东
KAC|科威特航空|亚洲与中东
GFA|海湾航空|亚洲与中东
RJA|皇家约旦航空|亚洲与中东
MEA|中东航空|亚洲与中东
PAL|菲律宾航空|亚洲与中东
QFA|澳洲航空|大洋洲
VOZ|维珍澳洲航空|大洋洲
FJI|斐济航空|大洋洲
ETH|埃塞俄比亚航空|非洲
SAA|南非航空|非洲
MSR|埃及航空|非洲
SEY|塞舌尔航空|非洲
REU|留尼汪航空|非洲
BOE|波音原厂涂装|美洲'''.splitlines():
 code,name,region=row.split('|');NAMES[code]=(name,region)
SPECIAL={'CCA-SA':'星空联盟','CES_ST':'天合联盟','HVN_ST':'天合联盟','GIA_ST':'天合联盟','SVA_ST':'天合联盟','AFL-ST':'天合联盟','TAP-SA':'星空联盟','MSR-SA':'星空联盟','THY-SA':'星空联盟','ACA-SA':'星空联盟','SAS-SA':'星空联盟','CPA-OW':'寰宇一家','CPA_1K':'第 1,000 架空客','QFA-OW':'寰宇一家','MAS-OW':'寰宇一家','ETD1':'阿布扎比 F1','ETD_EXPO':'米兰世博会','GFA2':'巴林 F1','AZU2':'巴西国旗','AZU3':'特别涂装','KLM-100':'100 周年','KLM-100-2':'100 周年 · B787-10','KLM-2014-100':'100 周年 · 新版','KLM-95':'95 周年','FIN-MU':'Marimekko Unikko','FIN-MK':'Marimekko Kivet','FIN-OW':'寰宇一家','QTR-OW':'寰宇一家','ETH-SA':'星空联盟','SIA-10000':'第 10,000 架空客','JAL-RED':'A350 红色纪念','JAL-SILVER':'A350 银色纪念','JAL-GREEN':'A350 绿色纪念','JAL-CASTLE':'首里城','DAL-SPIRIT':'The Delta Spirit','MAS-NEGARAKU':'Negaraku','TAM-FIRST':'首架 A350','SVA-NEOM':'NEOM','AEA-IGLESIAS':'Julio Iglesias','AEA-SCHOLAS':'Scholas','AEA-X':'特别涂装','LOT1':'100 周年','DLH2':'Sharkskin','THY2':'Istanbul 2020','ETD':'', 'UAE-BLUE':'世博会 · 蓝色','UAE-ORANGE':'世博会 · 橙色','UAE-GREEN':'世博会 · 绿色','THY-SUPBAT':'Batman v Superman','KLM100':'100 周年','SDM-LEO':'远东豹'}
def resolve(repo,path):
 p=PATHS[repo].get(path.lower())
 if p:return repo,p
 if repo=='extra':
  base='787' if path.startswith('787/') else '330' if path.startswith('A330/') else '350'
  alt=('Models/'+path.split('/',1)[1]) if base=='787' else ('Models/Liveries/'+path.split('/',1)[1])
  p=PATHS[base].get(alt.lower())
  if p:return base,p
 raise FileNotFoundError(repo+':'+path)
def fetch(repo,path):
 repo,path=resolve(repo,path);url='https://raw.githubusercontent.com/'+REPOS[repo]+'/'+TREES[repo]['sha']+'/'+urllib.parse.quote(path)
 ident=repo+'-'+hashlib.sha256(path.encode()).hexdigest()[:14]+Path(path).suffix;target=DEST/ident
 with LOCK:lock=LOCKS.setdefault(ident,threading.Lock())
 with lock:
  if not target.exists():
   cached=RESEARCH/REPOS[repo].replace('/','_')/path
   if cached.exists():data=cached.read_bytes()
   else:
    for attempt in range(4):
     try:data=urllib.request.urlopen(url,timeout=120).read();break
     except Exception:
      if attempt==3:raise
      time.sleep(1+attempt)
   target.write_bytes(data)
  data=target.read_bytes()
  with Image.open(target) as im:size=im.size;im.verify()
 return ident,{'file':ident,'url':url,'sha256':hashlib.sha256(data).hexdigest(),'size':list(size),'bytes':len(data)}
jobs=[]
def add(repo,p,plane,engine,code=None,label=None,special=None):jobs.append(dict(repo=repo,path=p,plane=plane,engine=engine,code=code,label=label,special=special))
# Original 8K 787 family plus compatible additional liveries; ignore blank and duplicates.
for repo in ['787','extra']:
 base=RESEARCH/'livery-metadata'/REPOS[repo].replace('/','_')
 for p in sorted(base.rglob('*.xml')):
  path=str(p.relative_to(base));prefix='Models/' if repo=='787' else '787/'
  if not path.startswith(prefix+'Liveries-') or '/Blank' in path:continue
  m=re.match(prefix+r'Liveries-(8|9|10)/(GEnx|Trent1000)/([^/]+).xml',path)
  if not m:continue
  v,e,key=m.groups()
  if repo=='extra' and key in ['EVA','KLM','DLH','VIR']:continue
  add(repo,path,{'8':'b788','9':'b789','10':'b78x'}[v],'genx' if e=='GEnx' else 'trent')
# Wide A330 catalog; original engine variants remain separate and accurately labelled.
selection={'A332RR':'CCA CCA-SA CES CES_ST CHH CRK SAA AEA MSR MSR-SA GIA VOZ FJI ETD ETD1 ETD_EXPO AZU AZU2 AVA KAC OMA SEY GFA GFA2 MEA HAL AAL',
'A332PW':'CSN DAL GRL HVN HVN_ST RJA TAP TAP-SA MAS RZO AUA THY-SA KAL BEL FWI ARG',
'A332GE':'QTR EVA QFA QFA-OW AFR EIN EWG IBE KLM THY',
'A333RR':'CCA CES CSN CPA CPA-OW CPA_1K ACA ACA-SA DLH DLH2 DLH3 THY THY2 THA SWR SAS SAS-SA SIA SVA SVA_ST GIA_ST ALK CEB XAX VIR',
'A333GE':'QFA CAL FIN KLM QTR THY IBE PAL EIN',
'A333PW':'DAL MAS MAS-OW AAL AAR KAL THA'}
for folder,keys in selection.items():
 for key in keys.split():
  path=f'Models/Liveries/{folder}/{key}.xml'
  if path.lower() in PATHS['330']:add('330',path,folder[:4].lower(),folder[4:].lower())
for p in sorted((RESEARCH/'livery-metadata'/REPOS['extra'].replace('/','_')/'A330').rglob('*.xml')):
 path=str(p.relative_to(RESEARCH/'livery-metadata'/REPOS['extra'].replace('/','_')));folder=p.parent.name
 if p.stem in ['AAL','KLM','SWR']:continue
 add('extra',path,folder[:4].lower(),folder[4:].lower())
for p in sorted((RESEARCH/'livery-metadata'/REPOS['extra'].replace('/','_')/'A350').glob('*.xml')):
 add('extra','A350/'+p.name,'a359','xwb')
for key,code,label,special in [('','AFR',None,False),('american','AAL',None,False),('Britsh','BAW',None,False),('CATHAY','CPA',None,False),('CATHAY94','CPA-1994','国泰航空 · 1994',False),('ETHIOPIAN','ETH',None,False),('ETIHAD','ETD',None,False),('India','AIC',None,False),('KLM','KLM',None,False),('KLM100','KLM100',None,True),('LATAM','TAM',None,False),('QUA','QTR',None,False),('ROS','SDM',None,False),('ROS2','SDM-LEO',None,True),('Turkish','THY',None,False),('SUPBAT','THY-SUPBAT',None,True),('biman','BBC',None,False),('emirates','UAE',None,False),('emirexpbleu','UAE-BLUE',None,True),('emirexporange','UAE-ORANGE',None,True),('emirexpvert','UAE-GREEN',None,True),('russe','AFL',None,False)]:add('777',f'777-VMD/Models/Liveries-300ER/AFR2{key}.xml','b77w','ge90',code,label,special)
def task(job):
 repo=job['repo'];path=job['path'];plane=job['plane'];engine=job['engine'];key=job['code'] or Path(path).stem
 code=key[:3];name,region=NAMES.get(code,(code,'亚洲与中东'));special=job['special'] if job['special'] is not None else key in SPECIAL and bool(SPECIAL[key])
 suffix=SPECIAL.get(key) or ('新版' if '201' in key else key[3:].strip('-_') if key!=code else '')
 title=job['label'] or name+(' · '+suffix if suffix else '')
 xmlfile=RESEARCH/'livery-metadata'/REPOS[repo].replace('/','_')/path
 if not xmlfile.exists():xmlfile=RESEARCH/REPOS[repo].replace('/','_')/path
 xml=E.parse(xmlfile);english=xml.findtext('.//livery/name') or title
 if 'fictional' in english.lower():raise ValueError('Fictional '+path)
 asset=plane+'-'+engine;slots=json.loads((ROOT/'Sources/Winglight/Resources/Models'/(asset+'.json')).read_text())['textureSlots'];mapping={}
 if plane.startswith('b78'):
  prefix='Models/' if repo=='787' else '787/'
  mapping['paint']=(repo,prefix+xml.findtext('.//texture-fuselage'));mapping['engine']=(repo,prefix+xml.findtext('.//texture-engines'));mapping['wings.png']=('787','Models/wings.png')
 elif plane.startswith('a33'):
  tex=xml.findtext('.//livery/texture')
  mapping['paint']=(repo,'Models/'+tex if repo=='330' else 'A330/'+tex.removeprefix('Liveries/'))
  mapping.update({s:('330','Models/'+s)for s in slots if s!='paint'})
 elif plane=='a359':
  mapping={'paint':(repo,'A350/'+Path(xml.findtext('.//livery/bodyWork/texture')).name),'wings.png':('350','Models/wings.png')}
 else:
  nodes=['livery','fuselage','fuselage1','fuselage2','fuselage3','fuselage4','fuselage5','fuselage6','fuselage7','fuselage8']
  for s,node in zip(['AFR2.png','AFR1.png','AFR3.png','AFR4.png','AFR5.png','AFR6.png','AFR7.png','AFR8.png','AFR9.png','AFR1rac.png'],nodes):mapping[s]=('777','777-VMD/Models/'+xml.findtext('.//'+node+'/texture'))
 files=[];sources=[]
 for s in slots:
  f,meta=fetch(*mapping[s]);files.append(f);sources.append(meta)
 main=slots.index('paint') if 'paint' in slots else slots.index('AFR1.png');resolution=sources[main]['size'][0]
 engineName={'genx':'GEnx','trent':'Trent 1000','rr':'Trent 700','pw':'PW4000','ge':'CF6-80E1','xwb':'Trent XWB','ge90':'GE90-115B'}[engine]
 ident=plane+'-'+engine+'-'+key+('-extra' if repo=='extra' else '')
 note=engineName+' · 原始贴图 '+str(resolution)+' px'+(' · 特殊彩绘' if special else '')
 row=dict(id=ident,code=code,title=title,english=english,region=region,aircraft=plane,model=asset,texture=files[main],textures=files,engineTexture=None,textureSize=sources[main]['size'],resolution=resolution,note=note,special=bool(special),sources=sources,metadataURL='https://raw.githubusercontent.com/'+REPOS[repo]+'/'+TREES[repo]['sha']+'/'+urllib.parse.quote(path))
 (LEGAL/(ident+'.xml')).write_bytes(xmlfile.read_bytes());print(ident,resolution,flush=True);return row
if __name__=='__main__':
 result=[];errors=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
  for job,future in zip(jobs,[pool.submit(task,j)for j in jobs]):
   try:result.append(future.result())
   except Exception as e:errors.append([job,str(e)]);print('ERROR',job,str(e),flush=True)
 (LEGAL/'catalog.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));(LEGAL/'errors.json').write_text(json.dumps(errors,ensure_ascii=False,indent=2))
 baseline=json.loads((DEST/'catalog.json').read_text());baseline=[x for x in baseline if x['aircraft'] in ['airbus','boeing']]
 (DEST/'catalog.json').write_text(json.dumps(baseline+result,ensure_ascii=False,indent=2));print('TOTAL',len(result),'ERRORS',len(errors),flush=True)
