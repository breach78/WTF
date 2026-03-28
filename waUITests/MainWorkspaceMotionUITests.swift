import XCTest

final class MainWorkspaceMotionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testKeyboardRetargetRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonTitle: "Keyboard Retarget",
            expectedSummaryPrefix: "keyboardRetarget:PASS",
            in: app
        )
    }

    func testClickSupersedeRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonTitle: "Click Supersede",
            expectedSummaryPrefix: "clickSupersede:PASS",
            in: app
        )
    }

    func testBottomRevealRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonTitle: "Bottom Reveal Join",
            expectedSummaryPrefix: "bottomRevealJoin:PASS",
            in: app
        )
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WA_UI_TEST_MODE"] = "motion-kernel"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("-WA_UI_TEST_MODE_MOTION_KERNEL")
        app.launch()
        XCTAssertTrue(app.staticTexts["Main Workspace Motion Kernel Harness"].waitForExistence(timeout: 10))
        return app
    }

    private func runHarnessScenario(
        buttonTitle: String,
        expectedSummaryPrefix: String,
        in app: XCUIApplication
    ) {
        let button = app.buttons[buttonTitle]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let resultField = app.textFields["Motion Result Field"]
        XCTAssertTrue(resultField.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedSummaryPrefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: resultField)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)

        let summaryField = app.textFields["Motion Summary Field"]
        XCTAssertTrue(summaryField.waitForExistence(timeout: 5))
        let summaryPredicate = NSPredicate(
            format: "value CONTAINS %@ AND value CONTAINS %@",
            "second-correction-count=",
            "horizontal-mode=oneStep"
        )
        let summaryExpectation = XCTNSPredicateExpectation(predicate: summaryPredicate, object: summaryField)
        XCTAssertEqual(XCTWaiter.wait(for: [summaryExpectation], timeout: 5), .completed)
    }
}
