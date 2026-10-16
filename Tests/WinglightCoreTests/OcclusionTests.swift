import XCTest
import simd
@testable import WinglightCore

final class OcclusionTests: XCTestCase {
    func plane() throws -> AirframeOcclusion {
        var data=Data("WBVH".utf8)
        func uint(_ v: UInt32) { var x=v.littleEndian;withUnsafeBytes(of:&x) { data.append(contentsOf:$0) } }
        func float(_ v: Float) { uint(v.bitPattern) }
        [1,2,1].forEach { uint(UInt32($0)) }
        [-1.0,-1,0,1,1,0].forEach { float(Float($0)) }
        [0,0,2,0].forEach { uint(UInt32($0)) }
        [-1.0,-1,0,1,-1,0,1,1,0,-1,-1,0,1,1,0,-1,1,0].forEach { float(Float($0)) }
        return try AirframeOcclusion(data:data)
    }
    func testOnlyGeometryBetweenEmitterAndCameraBlocks() throws {
        let mesh=try plane(),origin=SIMD3<Float>(0,0,-2)
        XCTAssertTrue(mesh.isOccluded(from:origin,toward:SIMD3(0,0,1),distance:4))
        XCTAssertFalse(mesh.isOccluded(from:origin,toward:SIMD3(0,0,1),distance:1))
        XCTAssertFalse(mesh.isOccluded(from:origin,toward:SIMD3(0,0,-1),distance:4))
        XCTAssertFalse(mesh.isOccluded(from:origin,toward:SIMD3(1,0,0),distance:4))
        XCTAssertFalse(mesh.isOccluded(from:SIMD3(2,0,-2),toward:SIMD3(0,0,1),distance:4))
        XCTAssertTrue(mesh.isOccluded(from:SIMD3(0,0,2),toward:SIMD3(0,0,-1),distance:4))
    }
    func testNumericalToleranceDoesNotSkipNearbyRealSurfaces() throws {
        let mesh=try plane()
        for distance: Float in [1,10,100,1000] {
            XCTAssertFalse(mesh.isOccluded(from:SIMD3(0,0,-0.0001),toward:SIMD3(0,0,1),distance:distance))
            XCTAssertTrue(mesh.isOccluded(from:SIMD3(0,0,-0.01),toward:SIMD3(0,0,1),distance:distance))
            XCTAssertTrue(mesh.isOccluded(from:SIMD3(0,0,-0.03),toward:SIMD3(0,0,1),distance:distance))
        }
    }
    func testPartialApertureMaskingAtEdge() throws {
        let mesh=try plane(),direction=SIMD3<Float>(0,0,1)
        XCTAssertEqual(mesh.visibility(from:SIMD3(0,0,-2),toward:direction,distance:4),0)
        XCTAssertEqual(mesh.visibility(from:SIMD3(2,0,-2),toward:direction,distance:4),1)
        let partial=mesh.visibility(from:SIMD3(1,0,-2),toward:direction,distance:4)
        XCTAssertGreaterThan(partial,0);XCTAssertLessThan(partial,1)
    }
    func testSharedTriangleEdgeDoesNotLeakLight() throws {
        let mesh=try plane()
        for p: Float in [-0.9,0,0.9] {
            XCTAssertTrue(mesh.isOccluded(from:SIMD3(p,p,-2),toward:SIMD3(0,0,1),distance:4))
        }
    }
    func testMalformedBVHRejected() {
        XCTAssertThrowsError(try AirframeOcclusion(data:Data("WBVH".utf8)))
        XCTAssertThrowsError(try AirframeOcclusion(data:Data(repeating:0,count:16)))
    }
}
