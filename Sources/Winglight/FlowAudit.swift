import Foundation
import simd
import WinglightCore

@MainActor enum FlowAudit {
    static func run(directory: String) {
        var rows=[[String:Any]]()
        for (asset,geometry) in AircraftGeometry.catalog.sorted(by:{$0.key<$1.key}) {
            guard let aircraft=Aircraft.allCases.first(where:{asset==$0.rawValue || asset.hasPrefix($0.rawValue+"-")}),let url=Bundle.module.url(forResource:asset,withExtension:"bvh",subdirectory:"Models"),let data=try? Data(contentsOf:url),let mesh=try? AirframeOcclusion(data:data) else { continue }
            let start=Date(),original=Airflow.segments(for:aircraft,geometry:geometry)
            let safe=Airflow.avoidingAirframe(original,mesh:mesh)
            var crossings=0,disconnected=0
            for (index,segment) in safe.enumerated() {
                let a=SIMD3(segment.start.x,segment.start.y,segment.start.z),b=SIMD3(segment.end.x,segment.end.y,segment.end.z)
                if mesh.firstIntersection(from:a,toward:b-a,distance:simd_distance(a,b)+0.0001,minimum:0.000001) != nil { crossings+=1 }
                if index%Airflow.samples>0 && segment.start != safe[index-1].end { disconnected+=1 }
            }
            let bounds=Airflow.motionBounds(for:geometry)
            var movingCrossings=0,farSamples=0,farMoved=0
            for sign: Float in [-1,1] {
                // Envelope of the production bank, pitch and translation at
                // the largest allowed motion intensity (1.75).
                var pose=simd_float4x4(simd_quatf(angle:sign*0.078*1.75,axis:SIMD3(0,0,1)))*simd_float4x4(simd_quatf(angle:sign*0.029*1.75,axis:SIMD3(1,0,0)))
                pose.columns.3=SIMD4(sign*0.16*1.75,sign*0.54*1.75,0,1)
                let inverse=pose.inverse
                for segment in safe {
                    func local(_ v: SIMD4<Float>) -> SIMD3<Float> {
                        let p=SIMD3(v.x,v.y,v.z),world=Airflow.worldPosition(p,transform:pose,bounds:bounds)
                        let extent=simd_abs(p)-SIMD3(bounds.x,bounds.y,bounds.z)
                        if max(extent.x,max(extent.y,extent.z))>=bounds.w {
                            farSamples+=1;if world != p { farMoved+=1 }
                        }
                        let q=inverse*SIMD4(world,1);return SIMD3(q.x,q.y,q.z)
                    }
                    let a=local(segment.start),b=local(segment.end)
                    if mesh.firstIntersection(from:a,toward:b-a,distance:simd_distance(a,b)+0.0001,minimum:0.000001) != nil { movingCrossings+=1 }
                }
            }
            let row: [String:Any]=["asset":asset,"inputPaths":original.count/Airflow.samples,"safePaths":safe.count/Airflow.samples,"checkedSegments":safe.count,"surfaceCrossings":crossings,"disconnectedSegments":disconnected,"motionPoses":2,"movingCrossings":movingCrossings,"farSamples":farSamples,"farMoved":farMoved,"seconds":Date().timeIntervalSince(start)]
            rows.append(row);print("FLOW",asset,row);fflush(stdout)
        }
        let out=URL(fileURLWithPath:directory,isDirectory:true);try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        if let data=try? JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:out.appendingPathComponent("flow.json")) }
    }
}
