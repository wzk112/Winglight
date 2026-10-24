import XCTest

@MainActor final class MobileUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    func testControlsAircraftLiveriesSettingsAndImmersionAcrossOrientations() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["选择机型"].firstMatch.waitForExistence(timeout:30))
        screenshot("landscape")
        app.buttons["选择机型"].firstMatch.tap()
        app.textFields.firstMatch.tap();app.textFields.firstMatch.typeText("A350\n")
        app.buttons["Airbus A350-900"].tap()
        XCTAssertTrue(app.buttons["选择机型"].firstMatch.waitForExistence(timeout:10))
        app.buttons["打开涂装库"].firstMatch.tap()
        let search=app.textFields["搜索航空公司或代码"]
        XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("CCA\n")
        app.buttons["素色"].tap()
        screenshot("liveries")
        app.buttons["dismissPanel"].tap()
        if app.buttons["openControls"].exists { app.buttons["openControls"].tap() }
        app.buttons.matching(NSPredicate(format:"label == '设置'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["渲染"].waitForExistence(timeout:10))
        app.buttons["灯光"].tap()
        XCTAssertTrue(app.switches["HDR 闪光"].waitForExistence(timeout:10))
        app.buttons["时间与地点"].tap()
        let city=app.buttons["cityMelbourne"]
        for _ in 0..<4 { if city.exists && city.isHittable { break };app.collectionViews.firstMatch.swipeUp() }
        city.tap()
        screenshot("solar-settings")
        app.buttons["dismissPanel"].tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["openControls"].exists || app.scrollViews["tabletSidebar"].exists)
        screenshot("portrait")
        app.buttons["沉浸模式"].tap()
        XCTAssertTrue(app.buttons["退出沉浸模式"].waitForExistence(timeout:5))
        app.buttons["退出沉浸模式"].tap()
        if app.buttons["openControls"].exists { app.buttons["openControls"].tap() }
        XCTAssertTrue(app.switches["按时间计算日照"].waitForExistence(timeout:10))
        screenshot("compact-controls")
        if app.buttons["dismissPanel"].exists { app.buttons["dismissPanel"].tap() }
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["openControls"].exists || app.scrollViews["tabletSidebar"].exists)
    }
    private func screenshot(_ name: String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
