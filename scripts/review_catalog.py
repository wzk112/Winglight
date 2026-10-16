"""Apply manually reviewed names and emit actual source dimensions + CSV."""
from pathlib import Path
import json,csv
from PIL import Image
r=Path(__file__).resolve().parents[1];l=r/'Sources/Winglight/Resources/Liveries'
fixes=json.loads((r/'ThirdParty/WidebodyLiveries/reviewed-labels.json').read_text())
cat=json.loads((l/'catalog.json').read_text())
for item in cat:
    if item['id'] in fixes:item['title'],item['special']=fixes[item['id']]
    if item['id']=='a359-xwb-CCA-SA-extra':item['english']='Air China · Star Alliance'
    if item['code'].startswith('CCA-'):item['special']=True
    item['textureSize']=list(Image.open(l/item['texture']).size)
(l/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2))
with (r/'LIVERY_CATALOG.csv').open('w') as f:
    w=csv.writer(f,lineterminator='\n');w.writerow(['aircraft','id','title','english','special','texture_width','texture_height','model','note'])
    for x in cat:w.writerow([x['aircraft'],x['id'],x['title'],x['english'],bool(x.get('special')),*x['textureSize'],x.get('model',x['aircraft']),x['note']])
print(len(cat),'entries')
