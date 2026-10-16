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
}
