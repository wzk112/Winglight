import simd

/// An analytic flow visualization: body displacement, swept-wing downwash and
/// counter-rotating tip wakes. It is not a measured flow field or a CFD solver.
public enum Airflow {
    public static let samples = 480
    public struct Segment {
        public var start: SIMD4<Float>
        public var end: SIMD4<Float>
    }
    private static func smooth(_ a: Float,_ b: Float,_ x: Float) -> Float {
        let t = min(1,max(0,(x-a)/(b-a)));return t*t*(3-2*t)
    }
    public static func motionBounds(for geometry: AircraftGeometry) -> SIMD4<Float> {
        SIMD4(Float(geometry.span)*0.5+2,Float(geometry.finHeight)+2,Float(geometry.length)*0.5+2,8)
    }
    /// Mirrors flowWorldPosition in Metal. Keep the near field attached to the
    /// collision-tested mesh, then return to world space within eight metres.
    public static func worldPosition(_ p: SIMD3<Float>,transform: simd_float4x4,bounds: SIMD4<Float>) -> SIMD3<Float> {
        let outside=simd_abs(p)-SIMD3(bounds.x,bounds.y,bounds.z)
        let influence=1-smooth(0,bounds.w,max(outside.x,max(outside.y,outside.z)))
        let moved=transform*SIMD4(p,1)
        return p+(SIMD3(moved.x,moved.y,moved.z)-p)*influence
    }
    public static func segments(for aircraft: Aircraft,geometry suppliedGeometry: AircraftGeometry? = nil) -> [Segment] {
        let body = Float(aircraft.bodyWidth)*0.5+0.22
        let halfLength = Float(aircraft.length)*0.5
        let halfSpan = Float(aircraft.span)*0.5
        let geometry=suppliedGeometry ?? aircraft.geometry,scale=Float(aircraft.length/39.47)
        let centerY=Float(geometry.bodyCenterY),wingRoot=Float(geometry.bodyCenterY-geometry.bodyWidth*0.38)
        var seeds = [SIMD2<Float>]()
        // Twelve staggered depth layers keep the flow volumetric when orbiting.
        for column in -18...18 {
            for (layer,y) in [Float(-28),-20,-13,-7,-3.0,-1.1,1.1,3.0,7,13,20,28].enumerated() {
                seeds.append(SIMD2(Float(column)*2.5*max(1,halfSpan/18)+(layer%2 == 0 ? -0.27 : 0.27),y*max(1,halfSpan/25)))
            }
        }
        // Closely spaced tubes resolve the fuselage displacement.
        for ring in [Float(0.55),1.0,1.65] {
            for i in 0..<16 {
                let angle=(Float(i)+0.5)*Float.pi/8
                seeds.append(SIMD2(cos(angle)*ring,sin(angle)*ring))
            }
        }
        // Tip seeds remain coherent as their wakes roll up downstream.
        for side: Float in [-1,1] {
            for radius: Float in [0.48,0.90,1.45,2.1] {
                for i in 0..<8 {
                    let angle=Float(i)*Float.pi/4
                    seeds.append(SIMD2(side*halfSpan*0.94+cos(angle)*radius,wingRoot+halfSpan*0.94*0.065-centerY+sin(angle)*radius))
                }
            }
        }
        var result = [Segment]();result.reserveCapacity(seeds.count*samples)
        for seed in seeds {
            var previous: SIMD3<Float>?, length: Float = 0
            for i in 0...samples {
                let z: Float = (-40+Float(i)*0.26)*scale
                let envelope = smooth(-halfLength-2,-11*scale,z)*(1-smooth(9*scale,halfLength+2,z))
                let radial = sqrt(simd_length_squared(seed)+body*body*envelope*envelope)/simd_length(seed)
                var p = SIMD3<Float>(seed.x*radial,centerY+seed.y*radial,z)
                let wing = max(0,1-pow(abs(p.x)/(halfSpan+1),6))
                let leading = -7*scale+abs(p.x)*0.38, trailing = 3*scale+abs(p.x)*0.12
                let wingProfile = smooth(leading-3,leading+1,z)*(1-smooth(trailing,trailing+5,z))
                let wingY: Float = wingRoot+abs(p.x)*0.065
                let deltaY = p.y-wingY
                p.y += (centerY+seed.y > wingRoot+abs(seed.x)*0.065 ? 1 : -1)*1.2*wing*wingProfile*exp(-deltaY*deltaY/7)
                for side: Float in [-1,1] {
                    let e = SIMD2<Float>(side*Float(geometry.engineXY[0]),Float(geometry.engineXY[1]))
                    let d = SIMD2(p.x,p.y)-e, r2 = simd_length_squared(d)
                    let influence = smooth(-11*scale,-7*scale,z)*(1-smooth(-3*scale,scale,z))
                    let gain = sqrt(1+1.85*influence*influence/max(r2,0.04))
                    p.x = e.x+d.x*gain;p.y = e.y+d.y*gain
                }
                // Split above/below the stabilizer and around the vertical fin.
                let tail=smooth(9*scale,14*scale,z)*(1-smooth(19*scale,23*scale,z))
                let tailY=Float(geometry.point("logo").y)
                let tailDelta=p.y-tailY
                p.y += (centerY+seed.y>tailY ? 1 : -1)*0.8*tail*exp(-tailDelta*tailDelta/3)*exp(-pow(p.x/7,4))
                let finHeight=Float(geometry.finHeight)
                let fin=tail*smooth(1.4,2.8,p.y)*(1-smooth(finHeight-1,finHeight+1,p.y))
                p.x += (seed.x>0 ? 1 : -1)*0.7*fin*exp(-p.x*p.x/2)
                let wake=smooth(6*scale,16*scale,z),downstream=max(0,z-6*scale)
                for side: Float in [-1,1] {
                    let coreX=side*halfSpan*0.94,coreY=wingRoot+halfSpan*0.94*0.065
                    let dx=p.x-coreX,dy=p.y-coreY,r2=dx*dx+dy*dy
                    let angle=side*downstream*0.19*wake*exp(-r2/12)*exp(-downstream/110)
                    p.x += cos(angle)*dx-sin(angle)*dy-dx
                    p.y += sin(angle)*dx+cos(angle)*dy-dy
                }
                p.y -= 1.15*wake*exp(-p.x*p.x/(halfSpan*halfSpan))*min(1,downstream/25)
                if let previous {
                    let next=length+simd_distance(previous,p)
                    result.append(Segment(start:SIMD4(previous,length),end:SIMD4(p,next)))
                    length=next
                }
                previous=p
            }
        }
        return result
    }
    /// Keep complete continuous paths only. A streamline beginning outside the
    /// airframe cannot enter it without crossing a triangle in the exact BVH.
    /// This also covers optional engine variants and thin wings/tail surfaces.
    public static func avoidingAirframe(_ segments: [Segment],mesh: AirframeOcclusion) -> [Segment] {
        var result=[Segment]();result.reserveCapacity(segments.count)
        for offset in stride(from:0,to:segments.count,by:samples) {
            let line=segments[offset..<min(offset+samples,segments.count)]
            let intersects=line.contains { segment in
                let a=SIMD3(segment.start.x,segment.start.y,segment.start.z)
                let b=SIMD3(segment.end.x,segment.end.y,segment.end.z)
                return mesh.firstIntersection(from:a,toward:b-a,distance:simd_distance(a,b)+0.0001,minimum:0.000001) != nil
            }
            if !intersects { result.append(contentsOf:line) }
        }
        return result
    }

}
