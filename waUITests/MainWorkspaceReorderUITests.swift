import XCTest

final class MainWorkspaceReorderUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testReorderCommitRegressionHarnessPasses() {
        let app = XCUIApplication()
        app.launchEnvironment["WA_UI_TEST_MODE"] = "motion-kernel"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("-WA_UI_TEST_MODE_MOTION_KERNEL")
        app.launch()

        let title = app.staticTexts["Main Workspace Motion Kernel Harness"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        let button = app.buttons["Reorder Commit"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let resultField = app.textFields["Motion Result Field"]
        XCTAssertTrue(resultField.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value CONTAINS %@", "reorderCommit:PASS")
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
