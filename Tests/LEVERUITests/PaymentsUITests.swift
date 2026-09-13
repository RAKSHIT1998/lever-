import XCTest

final class PaymentsUITests: XCTestCase {
    func testScanAndPayManualUPIAndLog() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sample-data", "-pro"]
        app.launch()
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 10))
        _ = app.buttons["opportunityCard"].firstMatch.waitForExistence(timeout: 10)
        app.swipeUp()
        let tools = app.buttons["toolsRow"]
        XCTAssertTrue(tools.waitForExistence(timeout: 8))
        tools.tap()
        XCTAssertTrue(app.buttons["tool-scanAndPay"].waitForExistence(timeout: 8))
        app.buttons["tool-scanAndPay"].tap()
        // Simulator has no camera: use the typed path.
        let typeButton = app.buttons["Type UPI ID"].firstMatch.exists ? app.buttons["Type UPI ID"].firstMatch : app.staticTexts["Type UPI ID"].firstMatch
        XCTAssertTrue(typeButton.waitForExistence(timeout: 8))
        typeButton.tap()
        let field = app.textFields["payManualField"].exists ? app.textFields["payManualField"] : app.textViews["payManualField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("upi://pay?pa=bluetokai@icici&pn=Blue%20Tokai%20Coffee&am=499&cu=INR")
        app.buttons["payManualContinue"].tap()
        XCTAssertTrue(app.staticTexts["Blue Tokai Coffee"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "scanpay"; shot.lifetime = .keepAlways; add(shot)
        // "Any UPI app" exists even without installed apps; tapping opens nothing in the sim but arms the log sheet.
        XCTAssertTrue(app.buttons["payWith-upi"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["tool-spending"].waitForExistence(timeout: 8))
        app.buttons["tool-spending"].tap()
        XCTAssertTrue(app.navigationBars["Spending"].waitForExistence(timeout: 8))
        sleep(2)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot2.name = "spending"; shot2.lifetime = .keepAlways; add(shot2)
    }
}
