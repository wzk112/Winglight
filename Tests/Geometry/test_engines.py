"""Check real engine assemblies, not a mirrored example of the shader."""
import sys, unittest, json
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from convert_models import ROOT, read_ac, upgrade_737_details, mesh

class EngineTests(unittest.TestCase):
    def testDonorRotorsAlignWithCalibratedAxisOnBothSides(self):
        objects=[o for f in ['LWing.ac','RWing.ac'] for o in read_ac(ROOT/'ThirdParty/737'/f)]
        upgrade_737_details(objects)
        fans=[o for o in objects if o['name'].lower()=='fan']
        self.assertEqual(len(fans),2)
        for fan in fans:
            center=(fan['vertices'].min(0)+fan['vertices'].max(0))*.5
            self.assertAlmostEqual(center[1],-1.20,places=5)
            self.assertAlmostEqual(abs(center[2]),5.164,places=5)

    def testNativeFanUVIsNotReplacedBySpinnerCoordinates(self):
        fan=next(o for o in read_ac(ROOT/'ThirdParty/Widebody/b777/777-300.ac') if o['name'].lower()=='lfan')
        fan['part']=6;fan['textureIndex']=12
        data,_=mesh([fan],'b77w')
        self.assertTrue(np.all(data[:,14]==12))
        source=np.array([uv for _,_,coords in fan['faces'] for uv in coords])
        self.assertTrue(np.allclose(data[:,12:14].min(0),source.min(0)))
        self.assertTrue(np.allclose(data[:,12:14].max(0),source.max(0)))

    def testAllBundledFanAxesRemainStableThroughFullRotation(self):
        profiles=json.loads((ROOT/'Sources/WinglightCore/Resources/Aircraft.json').read_text())
        for profile in profiles:
            data=np.fromfile(ROOT/'Sources/Winglight/Resources/Models'/(profile['id']+'.mesh'),dtype='<f4').reshape(-1,16)
            for side in [-1,1]:
                p=data[(data[:,15]==6)&(data[:,0]*side>0),:2]
                self.assertGreater(len(p),0,profile['id'])
                axis=np.array([side*profile['engineXY'][0],profile['engineXY'][1]])
                center=(p.min(0)+p.max(0))*.5
                self.assertLess(np.linalg.norm(center-axis),.002,profile['id'])
                for angle in np.linspace(0,2*np.pi,17):
                    r=np.array([[np.cos(angle),-np.sin(angle)],[np.sin(angle),np.cos(angle)]])
                    self.assertLess(np.linalg.norm(r@(center-axis)),.002,profile['id'])

if __name__=='__main__':unittest.main()
