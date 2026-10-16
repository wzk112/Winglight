import XCTest
import simd
@testable import WinglightCore

final class MotionTests: XCTestCase {
    func testSwitchOffDeceleratesWithoutResettingPhase() {
        var speed=EasedValue(1)
        speed.set(0,at:10,duration:1)
        XCTAssertEqual(speed.value(at:10),1)
        XCTAssertGreaterThan(speed.value(at:10.5),0)
        XCTAssertEqual(speed.integral(from:10,to:11),0.5,accuracy:1e-10)
        XCTAssertEqual(speed.integral(from:11,to:20),0,accuracy:1e-10)
        XCTAssertTrue(speed.isSettled(at:11))
    }
    func testRapidReversalIsContinuousAndIndependentOfFrameRate() {
        var speed=EasedValue(1)
        speed.set(0,at:0,duration:1)
        let before=speed.value(at:0.3)
        speed.set(1,at:0.3,duration:0.8)
        XCTAssertEqual(speed.value(at:0.3),before,accuracy:1e-10)
        let one=speed.integral(from:0.3,to:2)
        let steps=(0..<170).reduce(0.0) { $0+speed.integral(from:0.3+Double($1)*0.01,to:0.3+Double($1+1)*0.01) }
        XCTAssertEqual(one,steps,accuracy:1e-10)
        XCTAssertEqual(speed.value(at:2),1)
    }
    func testDenseFlowIsFiniteConnectedAndTravelsDownstream() {
        for aircraft in Aircraft.allCases {
            let lines=Airflow.segments(for:aircraft)
            XCTAssertEqual(lines.count,556*Airflow.samples)
            for (index,line) in lines.enumerated() {
                XCTAssertTrue((0..<4).allSatisfy { line.start[$0].isFinite && line.end[$0].isFinite })
                XCTAssertGreaterThan(line.end.z,line.start.z)
                XCTAssertGreaterThan(line.end.w,line.start.w)
                XCTAssertLessThan(simd_distance(SIMD3(line.start.x,line.start.y,line.start.z),SIMD3(line.end.x,line.end.y,line.end.z)),1.5)
                if index%Airflow.samples>0 { XCTAssertEqual(line.start,lines[index-1].end) }
            }
        }
    }
}
