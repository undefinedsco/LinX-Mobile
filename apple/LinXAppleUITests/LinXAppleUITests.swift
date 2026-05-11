import XCTest

final class LinXAppleUITests: XCTestCase {
    @MainActor
    func testLaunchesToLogin() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Continue with LinX Cloud"].waitForExistence(timeout: 5))
    }
}
