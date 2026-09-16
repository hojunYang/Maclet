import CoreGraphics
import XCTest
@testable import MacletApp

final class CleanKeyboardControllerTests: XCTestCase {
    func testIgnoresEveryKeyboardEventWithoutIgnoringMouseEvents() {
        XCTAssertTrue(CleanKeyboardEventFilter.shouldIgnore(.keyDown))
        XCTAssertTrue(CleanKeyboardEventFilter.shouldIgnore(.keyUp))
        XCTAssertTrue(CleanKeyboardEventFilter.shouldIgnore(.flagsChanged))
        XCTAssertFalse(CleanKeyboardEventFilter.shouldIgnore(.leftMouseDown))
        XCTAssertFalse(CleanKeyboardEventFilter.shouldIgnore(.leftMouseUp))
    }
}
