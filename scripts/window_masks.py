"""Cabin emission masks from the supplied reference paint's actual window pixels.
Geometric panes are used for 737, 777, 787 and A350; only painted rows need masks.
No generic dark-paint threshold is applied outside the reviewed UV window strips.
"""
from pathlib import Path
from PIL import Image
import numpy as np,json
root=Path(__file__).resolve().parents[1]/'Sources/Winglight/Resources'
cat=json.loads((root/'Liveries/catalog.json').read_text())
regions={
'airbus':[(.158,.090,.737,.104),(.158,.329,.737,.342)],
'a332':[(.240,.362,.847,.387),(.140,.824,.762,.850)],
'a333':[(.220,.374,.880,.399),(.110,.851,.785,.877)],
'b789-genx-cxa':[(.120,.161,.791,.174),(.120,.395,.791,.409)]}
report=[]
for asset,rects in regions.items():
 ac='b789' if asset.endswith('cxa') else asset;code='CXA' if asset.endswith('cxa') else 'CCA'
 row=next(r for r in cat if r['aircraft']==ac and r['code']==code)
 im=Image.open(root/'Liveries'/row['texture']).convert('RGB');im.thumbnail((4096,4096))
 a=np.asarray(im);h,w=a.shape[:2];mask=np.zeros((h,w),np.uint8);count=0
 for x0,y0,x1,y1 in rects:
  x0,y0,x1,y1=round(x0*w),round(y0*h),round(x1*w),round(y1*h)
  dark=a[y0:y1,x0:x1].max(2)<185;todo=set(zip(*np.nonzero(dark)))
  while todo:
   start=todo.pop();component=[start];stack=[start]
   while stack:
    y,x=stack.pop()
    for q in [(y-1,x),(y+1,x),(y,x-1),(y,x+1)]:
     if q in todo:todo.remove(q);stack.append(q);component.append(q)
   ys,xs=np.array(component).T;ww=xs.max()-xs.min()+1;hh=ys.max()-ys.min()+1
   if .002*w<ww<.011*w and .003*h<hh<.024*h and len(component)>ww*hh*.24:
    mask[ys+y0,xs+x0]=255;count+=1
 assert count>60,(asset,count)
 Image.fromarray(mask).convert('RGBA').save(root/'Models'/(asset+'-windows.png'))
 report.append(dict(asset=asset,reference=row['id'],panes=count,size=[w,h],uvStrips=rects))
 print(asset,count,flush=True)
(root/'Models/window-masks.json').write_text(json.dumps(report,indent=2))
