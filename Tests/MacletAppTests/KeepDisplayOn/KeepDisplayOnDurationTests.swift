import XCTest
@testable import MacletApp

final class KeepDisplayOnDurationTests: XCTestCase {
    func testRemainingTextAlwaysShowsHoursMinutesAndSeconds() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let end = now.addingTimeInterval(3_723)

        XCTAssertEqual(
            KeepDisplayOnDuration.hours(4).remainingText(until: end, now: now),
            "01:02:03"
        )
    }

    func testInfiniteRemainingTextUsesInfinitySymbol() {
        XCTAssertEqual(KeepDisplayOnDuration.infinite.remainingText(until: nil), "∞")
    }
}
