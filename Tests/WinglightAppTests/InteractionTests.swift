import XCTest
import CoreLocation
import Combine
@testable import Winglight

final class InteractionTests: XCTestCase {
    @MainActor private func state() -> AppState {
        AppState(solar:SolarController(manager:CLLocationManager(),preferences:UserDefaults(suiteName:"Winglight.InteractionTests")!,automatic:false))
    }
    @MainActor func testOrbitInputRendersWithoutRebuildingPanels() {
        let state=state()
        var panels=0,frames=0
        let a=state.objectWillChange.sink { panels+=1 },b=state.renderRequests.sink { frames+=1 }
        for _ in 0..<240 { state.cameraYaw+=0.001;state.cameraPitch-=0.001;state.cameraDistance+=0.01 }
        XCTAssertEqual(panels,0)
        XCTAssertEqual(frames,720)
        state.setView(.front)
        XCTAssertEqual(state.viewPreset,.front);XCTAssertEqual(panels,1)
        withExtendedLifetime((a,b)) {}
    }
    @MainActor func testPanelReplacementCannotRevealStalePanelOnClose() {
        let state=state()
        state.showAircraft=true;state.showSettings=true
        XCTAssertFalse(state.showAircraft);XCTAssertTrue(state.showSettings)
        state.showSettings=false;XCTAssertNil(state.activePanel)
        state.showLiveries=true;state.showInfo=true
        state.showLiveries=false // a delayed dismiss cannot close the newer panel
        XCTAssertTrue(state.showInfo)
        state.showInfo=false;XCTAssertNil(state.activePanel)
    }
}
