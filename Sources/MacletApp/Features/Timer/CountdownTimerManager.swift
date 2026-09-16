import Combine
import Foundation
import MacletCore

enum CountdownTimerPhase: Equatable {
    case idle
    case running(endDate: Date, durationSeconds: Int)
    case paused(remainingSeconds: Int, durationSeconds: Int)

    var isActive: Bool {
        self != .idle
    }

    var isPaused: Bool {
        if case .paused = self {
            return true
        }
        return false
    }

    var durationSeconds: Int? {
        switch self {
        case .idle:
            return nil
        case .running(_, let durationSeconds), .paused(_, let durationSeconds):
            return durationSeconds
        }
    }

    func remainingSeconds(at date: Date) -> Int? {
        switch self {
        case .idle:
            return nil
        case .running(let endDate, _):
            return max(0, Int(ceil(endDate.timeIntervalSince(date))))
        case .paused(let remainingSeconds, _):
            return remainingSeconds
        }
    }
}

@MainActor
final class CountdownTimerManager: ObservableObject {
    @Published private(set) var phase: CountdownTimerPhase = .idle

    var onCompletion: ((Int) -> Void)?

    private var completionTimer: Timer?

    deinit {
        completionTimer?.invalidate()
    }

    func start(seconds: Int, now: Date = Date()) {
        guard (1...AppSettings.maximumTimerDurationSeconds).contains(seconds) else {
            return
        }

        invalidateCompletionTimer()
        let endDate = now.addingTimeInterval(TimeInterval(seconds))
        phase = .running(endDate: endDate, durationSeconds: seconds)
        scheduleCompletion(at: endDate)
    }

    func pause(now: Date = Date()) {
        guard case .running(_, let durationSeconds) = phase,
              let remainingSeconds = phase.remainingSeconds(at: now) else {
            return
        }

        guard remainingSeconds > 0 else {
            completeIfNeeded(now: now)
            return
        }

        invalidateCompletionTimer()
        phase = .paused(
            remainingSeconds: remainingSeconds,
            durationSeconds: durationSeconds
        )
    }

    func resume(now: Date = Date()) {
        guard case .paused(let remainingSeconds, let durationSeconds) = phase else {
            return
        }

        let endDate = now.addingTimeInterval(TimeInterval(remainingSeconds))
        phase = .running(endDate: endDate, durationSeconds: durationSeconds)
        scheduleCompletion(at: endDate)
    }

    func stop() {
        invalidateCompletionTimer()
        phase = .idle
    }

    func completeIfNeeded(now: Date = Date()) {
        guard case .running(let endDate, let durationSeconds) = phase else {
            return
        }

        guard endDate <= now else {
            return
        }

        invalidateCompletionTimer()
        phase = .idle
        onCompletion?(durationSeconds)
    }

    private func scheduleCompletion(at date: Date) {
        invalidateCompletionTimer()
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleCompletionTimerFired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        completionTimer = timer
    }

    private func handleCompletionTimerFired() {
        guard case .running(let endDate, _) = phase else {
            return
        }

        let now = Date()
        if endDate > now {
            scheduleCompletion(at: endDate)
        } else {
            completeIfNeeded(now: now)
        }
    }

    private func invalidateCompletionTimer() {
        completionTimer?.invalidate()
        completionTimer = nil
    }
}

struct TimerInput: Equatable {
    var hours = ""
    var minutes = ""
    var seconds = ""

    init(seconds totalSeconds: Int = 0) {
        guard totalSeconds > 0 else {
            return
        }
        hours = String(totalSeconds / 3_600)
        minutes = String((totalSeconds % 3_600) / 60)
        seconds = String(totalSeconds % 60)
    }

    var totalSeconds: Int? {
        guard isHoursValid, isMinutesValid, isSecondsValid else {
            return nil
        }

        let value = (Int(hours) ?? 0) * 3_600
            + (Int(minutes) ?? 0) * 60
            + (Int(seconds) ?? 0)
        return value > 0 ? value : nil
    }

    var isHoursValid: Bool {
        value(hours, isIn: 0...99)
    }

    var isMinutesValid: Bool {
        value(minutes, isIn: 0...59)
    }

    var isSecondsValid: Bool {
        value(seconds, isIn: 0...59)
    }

    mutating func sanitize() {
        hours = Self.digits(from: hours)
        minutes = Self.digits(from: minutes)
        seconds = Self.digits(from: seconds)
    }

    private func value(_ text: String, isIn range: ClosedRange<Int>) -> Bool {
        text.isEmpty || Int(text).map(range.contains) == true
    }

    private static func digits(from text: String) -> String {
        String(text.filter { $0 >= "0" && $0 <= "9" }.prefix(2))
    }
}

enum CountdownText {
    static func clock(seconds: Int) -> String {
        let seconds = max(0, seconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func preset(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if remainingSeconds > 0 { parts.append("\(remainingSeconds)s") }
        return parts.joined(separator: " ")
    }
}
