import Foundation
import simd
import WinglightCore

@MainActor enum LightingAudit {
    static func run(directory: String) {
        var report=[[String:Any]]()
        for (asset,geometry) in AircraftGeometry.catalog.sorted(by:{$0.key<$1.key}) {
            guard let aircraft=Aircraft.allCases.first(where:{asset==$0.rawValue || asset.hasPrefix($0.rawValue+"-")}),let url=Bundle.module.url(forResource:asset,withExtension:"bvh",subdirectory:"Models"),let data=try? Data(contentsOf:url),let mesh=try? AirframeOcclusion(data:data) else { continue }
            var settings=LightSettings();settings.aircraft=aircraft;settings.geometry=geometry;settings.landing=true
            for lamp in Lighting.lamps(at:0.015,settings:settings) {
                var direct=SIMD3<Float>(0,0,-1)
                switch lamp.emission {
                case .portNavigation,.portStrobe:direct=SIMD3(-1,0,0)
                case .starboardNavigation,.starboardStrobe:direct=SIMD3(1,0,0)
                case .tailNavigation,.tailStrobe:direct=SIMD3(0,0,1)
                case .upperBeacon:direct=SIMD3(0,1,0)
                case .lowerBeacon:direct=SIMD3(0,-1,0)
                case .logoPort:direct=simd_normalize(SIMD3(0.6,1,0))
                case .logoStarboard:direct=simd_normalize(SIMD3(-0.6,1,0))
                default:break
                }
                var eligible=0,blocked=0,close=0,nearest: Float=999
                for elevation in stride(from:-80.0,through:80.0,by:10) { for angle in stride(from:-180.0,to:180.0,by:5) {
                    let a=angle * .pi/180,e=elevation * .pi/180
                    let direction=SIMD3<Double>(sin(a)*cos(e),sin(e),-cos(a)*cos(e))
                    if Lighting.angularGain(lamp.emission,toward:direction)>0.05 {
                        eligible+=1
                        if let hit=mesh.firstIntersection(from:SIMD3(lamp.position),toward:SIMD3(direction),distance:200) { blocked+=1;nearest=min(nearest,hit);if hit<0.3 { close+=1 } }
                    }
                }}
                let outward=mesh.firstIntersection(from:SIMD3(lamp.position),toward:direct,distance:200)
                report.append(["asset":asset,"lamp":lamp.id,"position":[lamp.position.x,lamp.position.y,lamp.position.z],"eligible":eligible,"blocked":blocked,"blockedWithin30cm":close,"nearest":nearest,"outwardHit":outward ?? -1])
            }
        }
        let out=URL(fileURLWithPath:directory,isDirectory:true);try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:out.appendingPathComponent("occlusion.json")) }
    }
}
