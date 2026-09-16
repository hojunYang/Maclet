import XCTest
import MacletCore
@testable import MacletApp

@MainActor
final class CountdownTimerTests: XCTestCase {
    func testFeatureHeaderMetricsStayAlignedWithTimer() {
        XCTAssertEqual(CommandCenterMetrics.featureIconSize, 36)
        XCTAssertEqual(CommandCenterMetrics.featureSymbolSize, 16)
        XCTAssertEqual(CommandCenterMetrics.featureTitleSize, 11.5)
        XCTAssertEqual(CommandCenterMetrics.featureHeaderSpacing, 6)
        XCTAssertEqual(CommandCenterMetrics.featureCardPadding, 10)
        XCTAssertEqual(CommandCenterMetrics.featureHeaderLeadingInset, 14)
        XCTAssertEqual(CommandCenterMetrics.featureHeaderTopInset, 14)
        XCTAssertEqual(CommandCenterMetrics.featureCardCornerRadius, 32)
        XCTAssertEqual(CommandCenterMetrics.actionHeight, 24)
    }

    func testCommandCenterModulesFollowGridSpans() {
        XCTAssertEqual(CommandCenterLayout.unit, 64)
        XCTAssertEqual(CommandCenterLayout.gap, 12)

        let timerSize = CommandCenterLayout.size(CommandCenterLayout.timer)
        let keepDisplayOnSize = CommandCenterLayout.size(CommandCenterLayout.keepDisplayOn)
        let smallActionSize = CommandCenterLayout.size(CommandCenterLayout.keepAwake)
        let cleanKeyboardSize = CommandCenterLayout.size(CommandCenterLayout.cleanKeyboard)

        XCTAssertEqual(timerSize.width, CommandCenterLayout.span(4))
        XCTAssertEqual(timerSize.height, CommandCenterLayout.span(2))
        XCTAssertEqual(keepDisplayOnSize.width, CommandCenterLayout.span(2))
        XCTAssertEqual(keepDisplayOnSize.height, CommandCenterLayout.span(2))
        XCTAssertEqual(smallActionSize.width, CommandCenterLayout.span(2))
        XCTAssertEqual(smallActionSize.height, CommandCenterLayout.span(1))
        XCTAssertEqual(cleanKeyboardSize.width, CommandCenterLayout.span(2))
        XCTAssertEqual(cleanKeyboardSize.height, CommandCenterLayout.span(1))
        XCTAssertEqual(timerSize.width, 292)
        XCTAssertEqual(timerSize.height, 140)
        XCTAssertEqual(keepDisplayOnSize.width, 140)
        XCTAssertEqual(keepDisplayOnSize.height, 140)
        XCTAssertEqual(smallActionSize.width, 140)
        XCTAssertEqual(smallActionSize.height, 64)
    }

    func testCommandCenterLayoutRemovesTimerHeightWhenFeatureIsHidden() {
        let withTimer = CommandCenterLayout.contentSize(
            featureOrder: AppFeature.allCases,
            enabledFeatures: [.timer],
            quickCommandCount: 0
        )
        let withoutTimer = CommandCenterLayout.contentSize(
            featureOrder: AppFeature.allCases,
            enabledFeatures: [],
            quickCommandCount: 0
        )

        XCTAssertEqual(
            withTimer.height - withoutTimer.height,
            CommandCenterLayout.size(CommandCenterLayout.timer).height + CommandCenterLayout.gap
        )
    }

    func testGridPackingUsesFourColumnsWithoutMovingLaterFeaturesAhead() {
        let placements = CommandCenterLayout.featurePlacements(
            featureOrder: [.keepDisplayOn, .keepAwake, .timer, .cleanKeyboard],
            enabledFeatures: [.keepDisplayOn, .keepAwake, .timer, .cleanKeyboard],
            quickCommandCount: 0
        )

        XCTAssertEqual(placements.map(\.feature), [.keepDisplayOn, .keepAwake, .timer, .cleanKeyboard])
        XCTAssertEqual(placements.first { $0.feature == .keepDisplayOn }?.row, 0)
        XCTAssertEqual(placements.first { $0.feature == .keepDisplayOn }?.column, 0)
        XCTAssertEqual(placements.first { $0.feature == .keepAwake }?.row, 0)
        XCTAssertEqual(placements.first { $0.feature == .keepAwake }?.column, 2)
        XCTAssertEqual(placements.first { $0.feature == .timer }?.row, 2)
        XCTAssertEqual(placements.first { $0.feature == .timer }?.column, 0)
        XCTAssertEqual(placements.first { $0.feature == .cleanKeyboard }?.row, 4)
        XCTAssertEqual(placements.first { $0.feature == .cleanKeyboard }?.column, 0)
        XCTAssertTrue(placements.allSatisfy { $0.column + $0.span.col <= 4 })
    }

    func testTimerCanStartPauseResumeAndStopWithoutClockWaiting() {
        let manager = CountdownTimerManager()
        let start = Date().addingTimeInterval(1_000)

        manager.start(seconds: 120, now: start)
        XCTAssertEqual(manager.phase.remainingSeconds(at: start), 120)

        manager.pause(now: start.addingTimeInterval(30))
        XCTAssertTrue(manager.phase.isPaused)
        XCTAssertEqual(manager.phase.remainingSeconds(at: start.addingTimeInterval(90)), 90)

        manager.resume(now: start.addingTimeInterval(100))
        XCTAssertFalse(manager.phase.isPaused)
        XCTAssertEqual(manager.phase.remainingSeconds(at: start.addingTimeInterval(130)), 60)

        manager.stop()
        XCTAssertEqual(manager.phase, .idle)
    }

    func testTimerCompletesExactlyOnce() {
        let manager = CountdownTimerManager()
        let start = Date().addingTimeInterval(1_000)
        var completions: [Int] = []
        manager.onCompletion = { completions.append($0) }

        manager.start(seconds: 10, now: start)
        manager.completeIfNeeded(now: start.addingTimeInterval(9))
        XCTAssertTrue(completions.isEmpty)

        manager.completeIfNeeded(now: start.addingTimeInterval(10))
        manager.completeIfNeeded(now: start.addingTimeInterval(20))

        XCTAssertEqual(completions, [10])
        XCTAssertEqual(manager.phase, .idle)
    }

    func testAppStatePublishesTimerCompletionAlert() {
        let manager = CountdownTimerManager()
        let appState = AppState(timerManager: manager)
        let start = Date().addingTimeInterval(1_000)

        manager.start(seconds: 25, now: start)
        manager.completeIfNeeded(now: start.addingTimeInterval(25))

        XCTAssertEqual(appState.alert?.title, "Timer Complete")
        XCTAssertEqual(appState.alert?.message, "The 00:25 timer has finished.")
    }

    func testTimerInputValidationAndSanitization() {
        var input = TimerInput()
        input.hours = "1a2"
        input.minutes = "60"
        input.seconds = "9!"
        input.sanitize()

        XCTAssertEqual(input.hours, "12")
        XCTAssertEqual(input.seconds, "9")
        XCTAssertNil(input.totalSeconds)

        input.minutes = "5"
        XCTAssertEqual(input.totalSeconds, 12 * 3_600 + 5 * 60 + 9)
    }

    func testCountdownTextUsesMinuteAndHourFormats() {
        XCTAssertEqual(CountdownText.clock(seconds: 59), "00:59")
        XCTAssertEqual(CountdownText.clock(seconds: 60), "01:00")
        XCTAssertEqual(CountdownText.clock(seconds: 3_600), "1:00:00")
    }

    func testStatusItemPrioritizesTimerAndShowsPause() {
        XCTAssertEqual(
            StatusItemPresentation.text(
                timerRemainingSeconds: 59,
                timerIsPaused: false,
                keepDisplayOnRemainingSeconds: 3_600,
                keepDisplayOnIsInfinite: false
            ),
            "00:59"
        )
        XCTAssertEqual(
            StatusItemPresentation.text(
                timerRemainingSeconds: 60,
                timerIsPaused: true,
                keepDisplayOnRemainingSeconds: nil,
                keepDisplayOnIsInfinite: true
            ),
            "⏸ 01:00"
        )
    }

    func testStatusItemFallsBackToKeepDisplayOnThenIconOnly() {
        XCTAssertEqual(
            StatusItemPresentation.text(
                timerRemainingSeconds: nil,
                timerIsPaused: false,
                keepDisplayOnRemainingSeconds: 3_600,
                keepDisplayOnIsInfinite: false
            ),
            "1:00:00"
        )
        XCTAssertEqual(
            StatusItemPresentation.text(
                timerRemainingSeconds: nil,
                timerIsPaused: false,
                keepDisplayOnRemainingSeconds: nil,
                keepDisplayOnIsInfinite: true
            ),
            "∞"
        )
        XCTAssertNil(
            StatusItemPresentation.text(
                timerRemainingSeconds: nil,
                timerIsPaused: false,
                keepDisplayOnRemainingSeconds: nil,
                keepDisplayOnIsInfinite: false
            )
        )
    }
}
