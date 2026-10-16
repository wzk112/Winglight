import XCTest
@testable import WinglightCore

final class SolarTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from:text)! }
    func testPositionAgainstPublishedSPACase() {
        // NREL TP-560-34302, Appendix A: 2003-10-17 12:30:30 MST,
        // 39.742476 N, 105.1786 W; azimuth 194.34024°, refracted zenith 50.11162°.
        // Our geometric altitude omits the example's atmospheric correction.
        let p=Solar.position(at:date("2003-10-17T19:30:30Z"),latitude:39.742476,longitude:-105.1786)
        XCTAssertEqual(p.azimuth,194.34024,accuracy:0.08)
        XCTAssertEqual(p.elevation,39.88838,accuracy:0.08)
        let events=Solar.events(on:date("2003-10-17T19:30:30Z"),latitude:39.742476,longitude:-105.1786,timeZone:TimeZone(secondsFromGMT:-7*3600)!)
        XCTAssertEqual(events.sunrise!.timeIntervalSince(date("2003-10-17T13:12:43Z")),0,accuracy:180)
        XCTAssertEqual(events.sunset!.timeIntervalSince(date("2003-10-18T00:20:19Z")),0,accuracy:180)
    }
    func testMelbourneDayAndNight() {
        let day=Solar.position(at:date("2026-10-16T02:00:00Z"),latitude:-37.8136,longitude:144.9631)
        let night=Solar.position(at:date("2026-10-16T14:00:00Z"),latitude:-37.8136,longitude:144.9631)
        XCTAssertGreaterThan(day.elevation,50);XCTAssertEqual(day.environment,2)
        XCTAssertLessThan(night.elevation,-12);XCTAssertEqual(night.environment,0)
    }
    func testPolarDayAndNightHaveNoInventedRiseSet() {
        let zone=TimeZone(secondsFromGMT:0)!
        let summer=Solar.events(on:date("2026-06-21T12:00:00Z"),latitude:78,longitude:15,timeZone:zone)
        let winter=Solar.events(on:date("2026-12-21T12:00:00Z"),latitude:78,longitude:15,timeZone:zone)
        XCTAssertNil(summer.sunrise);XCTAssertNil(summer.sunset);XCTAssertTrue(summer.polarDay)
        XCTAssertNil(winter.sunrise);XCTAssertNil(winter.sunset);XCTAssertFalse(winter.polarDay)
    }
    func testDSTLocalDayBoundaries() {
        let zone=TimeZone(identifier:"Australia/Melbourne")!
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let d=date("2026-10-04T02:00:00Z"),start=calendar.startOfDay(for:d),end=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:d))!
        XCTAssertEqual(end.timeIntervalSince(start),23*3600)
        let events=Solar.events(on:d,latitude:-37.8136,longitude:144.9631,timeZone:zone)
        XCTAssertGreaterThan(events.sunrise!,start);XCTAssertLessThan(events.sunset!,end)
        XCTAssertLessThan(events.sunrise!,events.sunset!)
    }
}
