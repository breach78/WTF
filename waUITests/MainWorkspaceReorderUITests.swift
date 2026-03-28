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
        app.launch()

        let title = app.staticTexts["motion-harness-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let button = app.buttons["motion-reorderCommit-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()

        let resultField = app.textFields["motion-result-field"]
        XCTAssertTrue(resultField.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value CONTAINS %@", "reorderCommit:PASS")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: resultField)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
