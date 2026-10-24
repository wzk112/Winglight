import Foundation
import simd

/// Static airframe acceleration structure built from the exact rendered mesh.
/// Rays use physical metre coordinates, independent of display resolution.
public struct AirframeOcclusion: Sendable {
    struct Node: Sendable { var low: SIMD3<Float>;var high: SIMD3<Float>;var left: Int;var right: Int;var count: Int }
    struct Triangle: Sendable { var a: SIMD3<Float>;var b: SIMD3<Float>;var c: SIMD3<Float> }
    let nodes: [Node]
    let triangles: [Triangle]
    public var storageByteCount: Int { nodes.count*MemoryLayout<Node>.stride+triangles.count*MemoryLayout<Triangle>.stride }
    public init(data: Data) throws {
        guard data.count>=16,String(data:data.prefix(4),encoding:.ascii)=="WBVH" else { throw CocoaError(.fileReadCorruptFile) }
        let parsed: ([Node],[Triangle]) = try data.withUnsafeBytes { raw in
            func uint(_ offset: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset:offset,as:UInt32.self)) }
            let nc=uint(4),tc=uint(8)
            guard nc>0,tc>0,data.count==16+nc*40+tc*36 else { throw CocoaError(.fileReadCorruptFile) }
            func vector(_ offset: Int) -> SIMD3<Float> {
                SIMD3(raw.loadUnaligned(fromByteOffset:offset,as:Float.self),raw.loadUnaligned(fromByteOffset:offset+4,as:Float.self),raw.loadUnaligned(fromByteOffset:offset+8,as:Float.self))
            }
            let nodes=(0..<nc).map { i in let p=16+i*40;return Node(low:vector(p),high:vector(p+12),left:uint(p+24),right:uint(p+28),count:uint(p+32)) }
            let triangles=(0..<tc).map { i in let p=16+nc*40+i*36;return Triangle(a:vector(p),b:vector(p+12),c:vector(p+24)) }
            return (nodes,triangles)
        }
        nodes=parsed.0;triangles=parsed.1
    }
    public func isOccluded(from origin: SIMD3<Float>,toward direction: SIMD3<Float>,distance: Float) -> Bool {
        firstIntersection(from:origin,toward:direction,distance:distance) != nil
    }
    public func firstIntersection(from origin: SIMD3<Float>,toward direction: SIMD3<Float>,distance: Float,minimum: Float = 0.0005) -> Float? {
        guard simd_length_squared(direction)>1e-12,distance.isFinite,distance>minimum else { return nil }
        let d=simd_normalize(direction)
        var nearest=distance
        func intersects(_ node: Node) -> Bool {
            var near=minimum,far=nearest
            for axis in 0..<3 {
                if abs(d[axis])<1e-8 {
                    if origin[axis]<node.low[axis] || origin[axis]>node.high[axis] { return false }
                } else {
                    let a=(node.low[axis]-origin[axis])/d[axis],b=(node.high[axis]-origin[axis])/d[axis]
                    near=max(near,min(a,b));far=min(far,max(a,b));if far<near { return false }
                }
            }
            return true
        }
        var stack=[0]
        while let index=stack.popLast() {
            let node=nodes[index];if !intersects(node) { continue }
            if node.count==0 { stack.append(node.left);stack.append(node.right);continue }
            for i in node.left..<(node.left+node.count) {
                let tri=triangles[i],e1=tri.b-tri.a,e2=tri.c-tri.a,p=simd_cross(d,e2),det=simd_dot(e1,p)
                if abs(det)<1e-8 { continue }
                let inv=1/det,s=origin-tri.a,u=simd_dot(s,p)*inv
                if u < -1e-6 || u > 1.000001 { continue }
                let q=simd_cross(s,e1),v=simd_dot(d,q)*inv
                if v < -1e-6 || u+v > 1.000001 { continue }
                let t=simd_dot(e2,q)*inv
                if t>minimum && t<nearest { nearest=t }
            }
        }
        return nearest<distance ? nearest : nil
    }
    /// Integrate a small emitting aperture. Partial masking changes amplitude,
    /// never pulse duration; the optical halo follows the visible source area.
    public func visibility(from origin: SIMD3<Float>,toward direction: SIMD3<Float>,distance: Float,radius: Float = 0.025,orthographic: Bool = false) -> Float {
        guard simd_length_squared(direction)>1e-12 else { return 0 }
        let d=simd_normalize(direction),reference=abs(d.y)>0.9 ? SIMD3<Float>(1,0,0) : SIMD3<Float>(0,1,0)
        let u=simd_normalize(simd_cross(d,reference)),v=simd_cross(d,u),camera=origin+d*distance
        var visible: Float=isOccluded(from:origin,toward:d,distance:distance) ? 0 : 0.25
        for i in 0..<12 {
            let angle=Float(i)*2*Float.pi/12
            let source=origin+(u*cos(angle)+v*sin(angle))*radius
            let toward=orthographic ? d : camera-source
            let length=orthographic ? distance : simd_length(toward)
            if !isOccluded(from:source,toward:toward,distance:length) { visible += 0.0625 }
        }
        return visible
    }
}
