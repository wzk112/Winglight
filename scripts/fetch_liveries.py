"""Fetch unmodified, pinned GPL-2 livery atlases; validate PNGs and write catalog.
Run with Python 3 + Pillow. All source URLs and hashes are retained in manifest.
"""
from pathlib import Path
import urllib.request,urllib.parse,json,hashlib,concurrent.futures,xml.etree.ElementTree as ET
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'Sources/Winglight/Resources/Liveries';DEST.mkdir(exist_ok=True)
CREDITS=ROOT/'ThirdParty/Liveries';CREDITS.mkdir(exist_ok=True)
REPOS={
 'a':('legoboyvdlp/A320-family-liveries','6673dc43d191163c1a4456b3bd7b00ace35f47f6'),
 'base':('legoboyvdlp/A320-family','fec1ecba767c8fffd145337b27012e89c01e3ade'),
 'b':('YV3399/737-800YV','9d967d89dd2ee0ae1bf01d00c49839a574aa9da5')}
# code | Chinese display name | region | source variant/key
A='''CCA|中国国际航空|中国|IAE
CES|中国东方航空|中国|CFM-NEO
HKE|香港快运|中国|PW-NEO
HDA|港龙航空|中国|IAE
AAL|美国航空|美洲|CFM
ACA|加拿大航空|美洲|CFM
AFR|法国航空|欧洲|CFM
AVA|哥伦比亚航空|美洲|CFM
AZA|意大利航空|欧洲|CFM
CFG|神鹰航空|欧洲|CFM
CSA|捷克航空|欧洲|CFM
CTN|克罗地亚航空|欧洲|CFM
DAL|达美航空|美洲|CFM
DLH|汉莎航空|欧洲|CFM
EDW|雪绒花航空|欧洲|CFM
EIN|爱尔兰航空|欧洲|CFM
ENT|Enter Air|欧洲|CFM
EWE|欧洲之翼|欧洲|CFM
EZY|易捷航空|欧洲|CFM
FIN|芬兰航空|欧洲|CFM
IBS|伊比利亚快运|欧洲|CFM
IRA|伊朗航空|亚洲与中东|CFM
LAO|老挝航空|亚洲与中东|CFM
PGT|飞马航空|欧洲|CFM
SBI|S7 航空|欧洲|CFM
TAM|LATAM 巴西航空|美洲|CFM
TAP|葡萄牙航空|欧洲|CFM
ASL|塞尔维亚航空|欧洲|IAE
BAW|英国航空|欧洲|IAE
JBU|捷蓝航空|美洲|IAE
JST|捷星航空|大洋洲|IAE
NKS|精神航空|美洲|IAE
SAA|南非航空|非洲|IAE
SEY|塞舌尔航空|非洲|IAE
THY|土耳其航空|欧洲|IAE
VIV|Viva Aerobus|美洲|IAE
VTI|Vistara|亚洲与中东|IAE
WZZ|维兹航空|欧洲|IAE
ANA|全日空|亚洲与中东|PW-NEO
IGO|靛蓝航空|亚洲与中东|PW-NEO
KZR|阿斯塔纳航空|亚洲与中东|PW-NEO
VOI|Volaris|美洲|PW-NEO
AXB|印度快运航空|亚洲与中东|CFM-NEO
DRK|不丹航空 Drukair|亚洲与中东|CFM-NEO
IBE|伊比利亚航空|欧洲|CFM-NEO
SAS|北欧航空|欧洲|CFM-NEO
SKU|智利天空航空|美洲|CFM-NEO
QTR|卡塔尔航空|亚洲与中东|base:IAE
AUA|奥地利航空|欧洲|base:CFM
SWR|瑞士国际航空|欧洲|base:CFM'''
B='''CCA|中国国际航空|中国|CCA
CES|中国东方航空|中国|CES
CHH|海南航空|中国|CHH
CAL|中华航空|中国|CAL
CCA-SILVER|国航 · 银牡丹|中国|B-5178
CCA-GOLD|国航 · 金牡丹|中国|B-5390
CCA-YELLOW|国航 · 黄牡丹|中国|B-5198
AAL|美国航空|美洲|AAL
DAL|达美航空|美洲|DAL
SWA|美国西南航空|美洲|SWA-new
ASA|阿拉斯加航空|美洲|ASA2
WJA|西捷航空|美洲|WJA2
AMX|墨西哥航空|美洲|AMX-DJK
CMP|巴拿马航空|美洲|CMP
ARG|阿根廷航空|美洲|ARG
GOL|巴西高尔航空|美洲|GOL nova
SCX|太阳城航空|美洲|SCX-2018
SWG|太阳之翼|美洲|SWG
ANA|全日空|亚洲与中东|ANA
JAL|日本航空|亚洲与中东|JAL
JTA|日本越洋航空|亚洲与中东|JTA
KAL|大韩航空|亚洲与中东|KAL
ESR|易斯达航空|亚洲与中东|ESR
MAS|马来西亚航空|亚洲与中东|MAS
GIA|印度尼西亚鹰航|亚洲与中东|GIA
LNI|狮子航空|亚洲与中东|LNI
FDB|迪拜航空|亚洲与中东|FDB
ELY|以色列航空|亚洲与中东|ELY
VT-AXA|印度快运航空|亚洲与中东|VT-AXA
NOK|泰国皇雀航空|亚洲与中东|NOK
FJI|斐济航空|大洋洲|FJI
QFA|澳洲航空|大洋洲|QFA-new
VOZ|维珍澳洲航空|大洋洲|VOZ
KLM|荷兰皇家航空|欧洲|KLM
RYR|瑞安航空|欧洲|RYR
THY|土耳其航空|欧洲|THY
PGT|飞马航空|欧洲|PGT
NAX|挪威航空|欧洲|NAX
TUI|途易航空|欧洲|TUI
EXS|Jet2|欧洲|EXS
AEA|欧罗巴航空|欧洲|AEA
SAS|北欧航空|欧洲|SAS
LOT|波兰航空|欧洲|LOT
AFL|俄罗斯航空|欧洲|AFL
SBI|S7 航空|欧洲|SBI
AUI|乌克兰国际航空|欧洲|AUI
ROT|罗马尼亚航空|欧洲|ROT
SXS|太阳快运航空|欧洲|SXS
TVS|Smartwings|欧洲|TVS
BRU|白俄罗斯航空|欧洲|BRU-2016
KQA|肯尼亚航空|非洲|KQA
ETH|埃塞俄比亚航空|非洲|ETH
MSR|埃及航空|非洲|MSR new
SAA|南非航空|非洲|SAA
CAI|Corendon Airlines|欧洲|CAI
BAW|英国航空 · Comair|非洲|BA
BMS|蓝天航空 Blue Air|欧洲|BMS
ENT|Enter Air|欧洲|ENT'''
def url(repo,path):
 name,sha=REPOS[repo];return 'https://raw.githubusercontent.com/'+name+'/'+sha+'/'+urllib.parse.quote(path)
def fetch(repo,path,dest):
 dest.parent.mkdir(parents=True,exist_ok=True)
 if not dest.exists():
  payload=urllib.request.urlopen(url(repo,path),timeout=45).read()
  tmp=dest.with_suffix(dest.suffix+'.partial');tmp.write_bytes(payload);tmp.replace(dest)
 return {'url':url(repo,path),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'bytes':dest.stat().st_size}
def task(row,aircraft):
 code,title,region,key=row.split('|');repo='a' if aircraft=='airbus' else 'b'
 if ':' in key:repo,key=key.split(':')
 prefix=('Models/Liveries/' if repo=='base' else 'Liveries/')+key if aircraft=='airbus' else ('Liveries-800' if repo=='extra' else 'Models/Liveries-800')
 xmlpath=prefix+'/'+(code if aircraft=='airbus' else key)+'.xml'
 ident=aircraft+'-'+code;xmlfile=CREDITS/(ident+'.xml');xmlmeta=fetch(repo,xmlpath,xmlfile)
 xml=ET.fromstring(xmlfile.read_bytes());originalName=xml.findtext('.//livery/name') or title
 if 'fictional' in originalName.lower():raise ValueError('Fictional livery: '+ident)
 path=(prefix+('/8k/' if code=='CCA' else '/4k/')+code+'-fuselage.png') if aircraft=='airbus' else prefix+'/'+key+'.png'
 filename=ident+'.png';meta=fetch(repo,path,DEST/filename)
 with Image.open(DEST/filename) as im:im.verify()
 with Image.open(DEST/filename) as im:width,height=im.size
 note='源涂装版本；机身与翼尖构型适配'
 if aircraft=='airbus':note='CFM56 机身适配' if key=='CFM' else ('原型 '+key+'；适配当前 CFM56 机身')
 if code in ['AZA','CSA','HDA','VTI','BMS','BAW'] and (aircraft=='boeing' or code!='BAW'):note+=' · 历史涂装'
 record={'id':ident,'code':code,'title':title,'english':originalName.replace(' (??-??)',''),'region':region,'aircraft':aircraft,'texture':filename,'engineTexture':None,'resolution':width,'note':note,'source':meta,'metadata':xmlmeta}
 # Only CFM56 engine UVs fit the bundled nacelle. Never map an IAE/LEAP atlas onto it.
 if aircraft=='airbus' and key=='CFM':
  engine=xml.findtext('.//livery/texture-engine')
  if engine:
   engine_repo=repo;enginepath=prefix+'/2k/'+engine
   target=DEST/('engine-'+code+'.png')
   try:record['engineSource']=fetch(engine_repo,enginepath,target)
   except Exception:
    if engine=='CFM56-white.png':record['engineSource']=fetch('base','Models/Liveries/CFM/2k/'+engine,target)
    else:raise
   with Image.open(target) as im:im.verify()
   record['engineTexture']=target.name
 print(ident,width,flush=True)
 return record
if __name__=='__main__':
 jobs=[(r,a) for a,rows in [('airbus',A),('boeing',B)] for r in rows.splitlines() if r]
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:records=list(pool.map(lambda x:task(*x),jobs))
 (DEST/'catalog.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
 for key in ['a','base','b']:
  fetch(key,'LICENSE',CREDITS/(key+'-LICENSE.txt'))
 (CREDITS/'manifest.json').write_text(json.dumps({'repositories':REPOS,'liveries':records},ensure_ascii=False,indent=2)+'\n')
 print('TOTAL',len(records),'PNG bytes',sum(p.stat().st_size for p in DEST.glob('*.png')))
