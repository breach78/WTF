import XCTest

final class MainWorkspaceMotionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testKeyboardRetargetRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonID: "motion-keyboardRetarget-button",
            expectedSummaryPrefix: "keyboardRetarget:PASS",
            in: app
        )
    }

    func testClickSupersedeRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonID: "motion-clickSupersede-button",
            expectedSummaryPrefix: "clickSupersede:PASS",
            in: app
        )
    }

    func testBottomRevealRegressionHarnessPasses() {
        let app = launchHarness()
        runHarnessScenario(
            buttonID: "motion-bottomRevealJoin-button",
            expectedSummaryPrefix: "bottomRevealJoin:PASS",
            in: app
        )
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WA_UI_TEST_MODE"] = "motion-kernel"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launch()
        XCTAssertTrue(app.staticTexts["motion-harness-title"].waitForExistence(timeout: 5))
        return app
    }

    private func runHarnessScenario(
        buttonID: String,
        expectedSummaryPrefix: String,
        in app: XCUIApplication
    ) {
        let button = app.buttons[buttonID]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let resultField = app.textFields["motion-result-field"]
        XCTAssertTrue(resultField.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedSummaryPrefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: resultField)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
