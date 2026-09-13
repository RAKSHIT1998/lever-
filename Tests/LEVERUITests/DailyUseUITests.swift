import XCTest

extension XCUIApplication {
    /// Taps a tab until it reports selected — taps can be dropped while SwiftData is mid-refresh on launch.
    func selectTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tabBars.buttons[name]
        for _ in 0..<4 {
            tab.tap()
            sleep(1)
            if tab.isSelected { return }
        }
        XCTFail("Could not select tab \(name)", file: file, line: line)
    }
}

final class DailyUseUITests: XCTestCase {
    func testEditPurchaseAndComposeClaim() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sample-data", "-pro"]
        app.launch()
        // Let the sample data seed and the first rule pass settle before querying the tree.
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 10))
        _ = app.buttons["opportunityCard"].firstMatch.waitForExistence(timeout: 10)
        app.selectTab("Vault")
        let row = app.staticTexts["Spotify Premium"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["purchaseEditButton"].waitForExistence(timeout: 5))
        app.buttons["purchaseEditButton"].tap()
        let title = app.textFields["editTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" (edited)")
        app.buttons["editSaveButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '(edited)'")).firstMatch.waitForExistence(timeout: 8))

        app.selectTab("Home")
        let card = app.buttons["opportunityCard"].firstMatch.exists ? app.buttons["opportunityCard"].firstMatch : app.otherElements["opportunityCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        app.swipeUp()
        if app.buttons["composeClaimButton"].waitForExistence(timeout: 3) {
            app.buttons["composeClaimButton"].tap()
            XCTAssertTrue(app.buttons["claimDraftButton"].waitForExistence(timeout: 5))
            app.buttons["claimDraftButton"].tap()
            XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.buttons["snoozeButton"].waitForExistence(timeout: 5))
        app.buttons["snoozeButton"].tap()
        XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5))
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 8))
    }
}
