import XCTest
@testable import Winglight
final class WeatherTests: XCTestCase {
    func testStormPeaksRespectHeadroomAndAccessibility() {
        let hdr=StormLighting.sample(time:3.21,strength:1,headroom:7,hdr:true,reduceMotion:false)
        XCTAssertGreaterThan(hdr.x,0.8);XCTAssertEqual(hdr.y,7)
        XCTAssertEqual(StormLighting.sample(time:3.21,strength:1,headroom:7,hdr:false,reduceMotion:false).y,1)
        XCTAssertEqual(StormLighting.sample(time:3.21,strength:1,headroom:7,hdr:true,reduceMotion:true).x,0)
        XCTAssertEqual(StormLighting.sample(time:3.21,strength:0,headroom:7,hdr:true,reduceMotion:false).x,0)
    }
    func testStormFlashesHaveQuietIntervalsAndStablePaths() {
        for time in [0.0,3.1,3.3,3.6,8,11.7] {
            XCTAssertEqual(StormLighting.sample(time:time,strength:1,headroom:3,hdr:true,reduceMotion:false).x,0)
        }
        let first=StormLighting.sample(time:3.21,strength:1,headroom:3,hdr:true,reduceMotion:false)
        let second=StormLighting.sample(time:3.39,strength:1,headroom:3,hdr:true,reduceMotion:false)
        XCTAssertEqual(first.z,second.z)
        XCTAssertNotEqual(first.z,StormLighting.sample(time:14.91,strength:1,headroom:3,hdr:true,reduceMotion:false).z)
    }
    func testReturnStrokesKeepChannelAndFadeBranches() {
        let initial=StormLighting.sample(time:3.21,strength:1,headroom:6,hdr:true,reduceMotion:false)
        let returns=(0..<350).map { i in
            StormLighting.sample(time:3.26+Double(i)*0.001,strength:1,headroom:6,hdr:true,reduceMotion:false)
        }.filter { $0.x>0 }
        XCTAssertFalse(returns.isEmpty)
        XCTAssertTrue(returns.allSatisfy { $0.z==initial.z && $0.w<initial.w && $0.x<initial.x })
        XCTAssertTrue(returns.allSatisfy { $0.x.isFinite && $0.x<=1 && $0.y==6 })
    }
    func testStormTimingVariesAcrossCyclesWithoutContinuousFlashing() {
        var starts=[Int]()
        for cycle in 0..<8 {
            var lit=0,first: Int?
            for tick in 0..<1170 {
                let s=StormLighting.sample(time:Double(cycle)*11.7+Double(tick)*0.01,strength:1,headroom:4,hdr:true,reduceMotion:false)
                XCTAssertTrue(s.x.isFinite && s.x>=0 && s.x<=1)
                if s.x>0 { lit+=1;if first==nil { first=tick } }
            }
            XCTAssertGreaterThan(lit,0);XCTAssertLessThan(lit,18)
            starts.append(first ?? -1)
        }
        XCTAssertGreaterThan(Set(starts).count,1)
    }
}
