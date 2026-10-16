"""Regression: concave and bridged window surrounds must never fill apertures."""
import sys,unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from convert_models import subdivide_surface,mesh,triangulate
class ApertureTests(unittest.TestCase):
 def surface(self,points):
  v=np.array([[x,0,z]for x,z in points],dtype=float)
  return dict(name='window-surround',file='test',texture='',vertices=v,faces=[(list(range(len(v))),16,points)])
 def area(self,data):
  t=data[:,:3].reshape(-1,3,3)
  return float(np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1).sum()/2)
 def testConcaveSurroundStaysOutsideWindow(self):
  o=self.surface([(0,0),(3,0),(3,3),(2,3),(2,1),(1,1),(1,3),(0,3)])
  subdivide_surface(o,2);data,_=mesh([o],'generic')
  self.assertAlmostEqual(self.area(data),7,places=5)
  centers=data[:,:3].reshape(-1,3,3).mean(1)
  self.assertFalse(np.any((centers[:,0]>1)&(centers[:,0]<2)&(centers[:,2]>1)))
 def testBridgedApertureDoesNotGetCentroidFan(self):
  o=self.surface([(0,0),(4,0),(4,4),(0,4),(0,0),(1,1),(1,3),(3,3),(3,1),(1,1)])
  t=triangulate(o['faces'][0][0],o['vertices']);p=o['vertices'][t]
  area=np.linalg.norm(np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]),axis=1).sum()/2
  self.assertAlmostEqual(area,12,places=5)
  subdivide_surface(o,2);data,_=mesh([o],'generic')
  self.assertAlmostEqual(self.area(data),12,places=5)
 def testThinWingNormalsDoNotMixOpposingSkins(self):
  o=dict(name='wing',file='test',texture='',crease=45,vertices=np.array([[0,0,0],[1,0,0],[0,0,2],[0,-.08,2]],float),faces=[([0,2,1],16,[[0,0]]*3),([0,1,3],16,[[0,0]]*3)])
  data,_=mesh([o],'generic')
  self.assertTrue(np.all(data[:3,5]>.99))
  self.assertTrue(np.all(data[3:,5]<-.99))
 def test777HasSixOriginalCockpitPanes(self):
  from convert_models import read_ac,ROOT
  panes=[o for o in read_ac(ROOT/'ThirdParty/Widebody/b777/flightdeck.ac') if o['texture']=='glass-alpha.png']
  self.assertEqual(sum(len(o['faces']) for o in panes),6)
 def testA350RetainsCabinGlazingButNotEditingCube(self):
  from convert_models import read_ac,ROOT
  from convert_widebody import keep,assign
  o=next(o for o in read_ac(ROOT/'ThirdParty/Widebody/a350/A350XWB-900.ac') if o['name']=='cabin.windows')
  self.assertTrue(keep(o,'a350'));assign(o,'a350','xwb',[])
  self.assertEqual(o['part'],13)
  self.assertTrue(np.all(o['vertices'][:,1]>1.8))
  self.assertLess(abs(o['vertices'][:,2]).max(),3.1)
  self.assertGreater(len(o['faces']),1500)
if __name__=='__main__':unittest.main()
