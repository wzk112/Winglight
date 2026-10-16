import XCTest
import CoreLocation
import Combine
@testable import Winglight

@MainActor private final class FakeLocationProvider: LocationProvider {
    weak var delegate: CLLocationManagerDelegate?
    var authorizationStatus = CLAuthorizationStatus.authorizedAlways
    var desiredAccuracy: CLLocationAccuracy = 0
    var starts=0,stops=0,permissionRequests=0
    func requestWhenInUseAuthorization() { permissionRequests += 1 }
    func startUpdatingLocation() { starts += 1 }
    func stopUpdatingLocation() { stops += 1 }
}

final class SolarControllerTests: XCTestCase {
    @MainActor func testManualTimeSurvivesRefreshAndRestoresClock() {
        let (solar,_,_,advance)=fixture()
        solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"Melbourne",timeZoneID:"Australia/Melbourne",persist:false)
        solar.setHour(22.5)
        XCTAssertEqual(solar.clock(solar.date),"22:30");XCTAssertNotNil(solar.manualDate)
        let manual=solar.date;advance();solar.refresh();XCTAssertEqual(solar.date,manual)
        XCTAssertLessThan(solar.position!.elevation,0)
        solar.restoreCurrentTime(animated:false)
        XCTAssertNil(solar.manualDate);XCTAssertEqual(solar.date,Date(timeIntervalSince1970:1_790_000_060))
    }
    @MainActor func testManualTimeUsesSelectedCityZoneAndClampsInvalidValues() {
        let (solar,_,_,_)=fixture()
        solar.setLocation(latitude:39.9,longitude:116.4,name:"Beijing",timeZoneID:"Asia/Shanghai",persist:false)
        solar.setHour(12.25);XCTAssertEqual(solar.clock(solar.date),"12:15")
        XCTAssertGreaterThan(solar.position!.elevation,0)
        solar.setHour(30);XCTAssertEqual(solar.clock(solar.date),"23:59")
        let date=solar.date;solar.setHour(.nan);XCTAssertEqual(solar.date,date)
        solar.setHour(-1);XCTAssertEqual(solar.clock(solar.date),"00:00")
    }
    @MainActor func testScrubbingCoalescesPointerEventsAndCommitsLastValue() {
        let (solar,_,_,_)=fixture()
        solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"Melbourne",timeZoneID:"Australia/Melbourne",persist:false)
        var samples=0
        let token=solar.objectWillChange.sink { samples+=1 }
        for i in 0..<240 { solar.previewHour(Double(i)/10) }
        XCTAssertTrue(solar.isScrubbing);XCTAssertEqual(samples,1)
        solar.endScrubbing()
        XCTAssertFalse(solar.isScrubbing);XCTAssertEqual(samples,2)
        XCTAssertEqual(solar.clock(solar.date),"23:54")
        withExtendedLifetime(token) {}
    }
    @MainActor func testSolarScrubDoesNotRebuildUnrelatedPanelsOrLagBehindTime() {
        let (solar,_,_,_)=fixture()
        solar.setLocation(latitude:-37.8136,longitude:144.9631,name:"Melbourne",timeZoneID:"Australia/Melbourne",persist:false)
        solar.setHour(11)
        let state=AppState(solar:solar)
        var panels=0,frames=0
        let a=state.objectWillChange.sink { panels+=1 },b=state.renderRequests.sink { frames+=1 }
        for i in 0..<60 { solar.setHour(11+Double(i)/60) }
        XCTAssertEqual(panels,0);XCTAssertGreaterThan(frames,50)
        solar.setHour(19.5)
        XCTAssertEqual(state.environmentValue,state.baseEnvironment,accuracy:0.0001)
        solar.setHour(23)
        XCTAssertEqual(state.environmentValue,state.baseEnvironment,accuracy:0.0001)
        XCTAssertLessThanOrEqual(panels,2)
        withExtendedLifetime((a,b)) {}
    }
    @MainActor private func fixture(status: CLAuthorizationStatus = .authorizedAlways) -> (SolarController,FakeLocationProvider,UserDefaults, () -> Void) {
        let provider=FakeLocationProvider();provider.authorizationStatus=status
        let preferences=UserDefaults(suiteName:"WinglightTests.\(UUID().uuidString)")!
        var date=Date(timeIntervalSince1970:1_790_000_000)
        let solar=SolarController(manager:provider,preferences:preferences,now:{date},automatic:false)
        return (solar,provider,preferences,{date=date.addingTimeInterval(60)})
    }
    @MainActor func testDelayedInitialAuthorizationStartsOnce() {
        let provider=FakeLocationProvider();provider.authorizationStatus = .notDetermined
        let preferences=UserDefaults(suiteName:"WinglightTests.\(UUID().uuidString)")!
        let solar=SolarController(manager:provider,preferences:preferences,automatic:true)
        XCTAssertEqual(provider.starts,0)
        provider.authorizationStatus = .authorizedAlways
        solar.authorizationChanged(.authorizedAlways)
        XCTAssertEqual(provider.starts,1);XCTAssertTrue(solar.requesting)
        solar.authorizationChanged(.authorizedAlways);XCTAssertEqual(provider.starts,1)
        solar.cancelLocation();solar.authorizationChanged(.authorizedAlways)
        XCTAssertFalse(solar.requesting);XCTAssertEqual(provider.starts,1)
    }
    @MainActor func testTemporaryFailureCannotLeaveRequestStuck() {
        let (solar,provider,_,advance)=fixture()
        solar.locate();XCTAssertEqual(provider.starts,1)
        solar.receive(error:CLError(.locationUnknown))
        XCTAssertTrue(solar.requesting)
        let stops=provider.stops
        advance();solar.checkLocationDeadline()
        XCTAssertFalse(solar.requesting);XCTAssertTrue(solar.locationIssue)
        XCTAssertEqual(provider.stops,stops+1)
        solar.locate();XCTAssertTrue(solar.requesting);XCTAssertEqual(provider.starts,2)
        solar.cancelLocation()
    }
    @MainActor func testPermissionWaitAndMacAuthorization() {
        let (solar,provider,_,advance)=fixture(status:.notDetermined)
        solar.locate();XCTAssertEqual(provider.permissionRequests,1);XCTAssertEqual(provider.starts,0)
        advance();solar.checkLocationDeadline();XCTAssertFalse(solar.requesting)
        solar.locate();provider.authorizationStatus = .authorizedAlways
        solar.authorizationChanged(.authorizedAlways)
        XCTAssertEqual(provider.starts,1);XCTAssertTrue(solar.requesting)
        solar.authorizationChanged(.authorizedAlways);XCTAssertEqual(provider.starts,1)
        solar.cancelLocation()
    }
    @MainActor func testManualCityCancelsRequestAndIgnoresLateFix() {
        let (solar,provider,preferences,_)=fixture()
        solar.locate();let stops=provider.stops
        solar.setLocation(latitude:51.5074,longitude:-0.1278,name:"伦敦",timeZoneID:"Europe/London")
        XCTAssertFalse(solar.requesting);XCTAssertEqual(provider.stops,stops+1)
        solar.receive([CLLocation(latitude:0,longitude:0)])
        XCTAssertEqual(solar.locationName,"伦敦")
        let restored=SolarController(manager:FakeLocationProvider(),preferences:preferences,automatic:false)
        XCTAssertEqual(restored.locationName,"伦敦");XCTAssertEqual(restored.timeZone.identifier,"Europe/London")
    }
    @MainActor func testValidFixStopsUpdatesAndRejectsStaleOrInvalidFixes() {
        let (solar,provider,_,_)=fixture();solar.locate()
        func fix(age: Double,accuracy: Double) -> CLLocation {
            CLLocation(coordinate:CLLocationCoordinate2D(latitude:-37.8,longitude:144.9),altitude:0,horizontalAccuracy:accuracy,verticalAccuracy:0,timestamp:Date(timeIntervalSince1970:1_790_000_000+age))
        }
        solar.receive([fix(age:-3600,accuracy:20),fix(age:0,accuracy:-1)])
        XCTAssertNil(solar.coordinate);XCTAssertTrue(solar.requesting)
        let stops=provider.stops
        solar.receive([fix(age:0,accuracy:100)])
        XCTAssertEqual(solar.coordinate?.latitude,-37.8);XCTAssertFalse(solar.requesting)
        XCTAssertTrue(solar.usesMacLocation);XCTAssertEqual(provider.stops,stops+1)
    }
    @MainActor func testDeniedAndNetworkFailuresStopAndCanRetry() {
        let (solar,provider,_,_)=fixture(status:.denied)
        solar.locate();XCTAssertFalse(solar.requesting);XCTAssertTrue(solar.locationIssue);XCTAssertEqual(provider.starts,0)
        provider.authorizationStatus = .authorizedAlways;solar.locate()
        solar.receive(error:CLError(.network));XCTAssertFalse(solar.requesting)
        solar.locate();XCTAssertEqual(provider.starts,2)
        solar.cancelLocation();solar.receive(error:CLError(.denied))
        XCTAssertFalse(solar.locationIssue)
    }
}
