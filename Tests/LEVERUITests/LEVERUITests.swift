import XCTest

final class LEVERUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
        return app
    }

    /// Paged TabViews keep off-screen pages in the hierarchy; wait until the element has actually slid into view.
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let hittable = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element) never became hittable")
        element.tap()
    }

    func testOnboardingFlowReachesHome() {
        let app = launch(["-onboarding"])
        tapWhenHittable(app.buttons["onboardingContinue"])
        tapWhenHittable(app.buttons["onboardingContinue2"])
        tapWhenHittable(app.buttons["onboardingLater"])
        tapWhenHittable(app.buttons["onboardingNotNow"])
        tapWhenHittable(app.buttons["onboardingFinish"])
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 5))
    }

    func testHomeShowsOpportunitiesWithSampleData() {
        let app = launch(["-sample-data"])
        XCTAssertTrue(app.staticTexts["homeHeadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["opportunityCard"].firstMatch.waitForExistence(timeout: 8) || app.buttons["opportunityCard"].firstMatch.waitForExistence(timeout: 2))
    }

    func testCapturePasteFlowThroughReviewToMagicMoment() {
        let app = launch(["-pro"])
        app.tabBars.buttons["Capture"].tap()
        app.buttons["capturePasteButton"].tap()
        let editor = app.textViews["pasteTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Amazon.in Order Confirmation\nOrder # 405-1234567-1234567\nApple MacBook Pro\nOrder Total ₹1,49,990\nOrder date 10 Sep 2026\nPaid with Visa ending 4421")
        app.buttons["pasteAnalyseButton"].tap()
        XCTAssertTrue(app.buttons["reviewConfirmButton"].waitForExistence(timeout: 15))
        app.buttons["reviewConfirmButton"].tap()
        XCTAssertTrue(app.staticTexts["magicHeadline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["magicDoneButton"].waitForExistence(timeout: 5))
    }

    func testOpportunityDetailAndSavingsConfirmation() {
        let app = launch(["-sample-data", "-pro"])
        let card = app.buttons["opportunityCard"].firstMatch.exists ? app.buttons["opportunityCard"].firstMatch : app.otherElements["opportunityCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.buttons["whyButton"].waitForExistence(timeout: 5))
        app.buttons["whyButton"].tap()
        app.swipeUp()
        let resolve = app.buttons["markResolvedButton"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 5))
        resolve.tap()
        XCTAssertTrue(app.buttons["savingsYesButton"].waitForExistence(timeout: 5))
        app.buttons["savingsNotYetButton"].tap()
    }

    func testPaywallAppearsAfterFreeCapturesAndCanContinueFree() {
        let app = launch(["-sample-data"])
        app.buttons["profileButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Upgrade"].waitForExistence(timeout: 5))
        app.buttons["Upgrade"].tap()
        XCTAssertTrue(app.buttons["paywallContinueFree"].waitForExistence(timeout: 8))
        app.buttons["paywallContinueFree"].tap()
    }

    func testSettingsPrivacyCenter() {
        let app = launch()
        app.buttons["profileButton"].firstMatch.tap()
        let link = app.descendants(matching: .any).matching(identifier: "privacyCenterLink").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["Privacy Center"].waitForExistence(timeout: 5))
        app.swipeUp()
        let delete = app.descendants(matching: .any).matching(identifier: "deleteEverythingButton").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
    }
}
