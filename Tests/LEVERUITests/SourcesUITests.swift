import XCTest

final class SourcesUITests: XCTestCase {
    func testSourcesScreenAndStatementPasteFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-pro", "-paste-fixture", "statement"]
        app.launch()
        app.tabBars.buttons["Capture"].tap()
        app.buttons["capturePasteButton"].tap()
        let analyse = app.buttons["pasteAnalyseButton"]
        XCTAssertTrue(analyse.waitForExistence(timeout: 5))
        analyse.tap()
        let importButton = app.buttons["statementImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot); attachment.name = "statement"; attachment.lifetime = .keepAlways
        add(attachment)
        importButton.tap()
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 10))

        app.buttons["profileButton"].firstMatch.tap()
        let link = app.descendants(matching: .any).matching(identifier: "sourcesLink").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.buttons["importStatementButton"].waitForExistence(timeout: 5))
        let shot2 = XCUIScreen.main.screenshot()
        let a2 = XCTAttachment(screenshot: shot2); a2.name = "sources"; a2.lifetime = .keepAlways
        add(a2)
    }
}
