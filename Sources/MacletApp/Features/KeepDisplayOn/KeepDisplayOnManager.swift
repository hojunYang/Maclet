import Foundation

enum KeepDisplayOnDuration: Equatable, Identifiable, Sendable {
    case off
    case minutes(Int)
    case hours(Int)
    case infinite

    static let controls: [KeepDisplayOnDuration] = [
        .minutes(15),
        .minutes(30),
        .minutes(45),
        .hours(1),
        .hours(4),
        .hours(8),
        .infinite
    ]

    var id: String {
        switch self {
        case .off:
            return "off"
        case .minutes(let value):
            return "minutes-\(value)"
        case .hours(let value):
            return "hours-\(value)"
        case .infinite:
            return "infinite"
        }
    }

    var label: String {
        switch self {
        case .off:
            return "Off"
        case .minutes(let value):
            return "\(value)"
        case .hours(let value):
            return "\(value)h"
        case .infinite:
            return "∞"
        }
    }

    var durationSeconds: Int? {
        switch self {
        case .off, .infinite:
            return nil
        case .minutes(let value):
            return value * 60
        case .hours(let value):
            return value * 60 * 60
        }
    }

    var keepsDisplayOn: Bool {
        self != .off
    }

    func remainingText(until activeUntil: Date?, now: Date = Date()) -> String {
        switch self {
        case .off:
            return "00:00:00"
        case .infinite:
            return "∞"
        case .minutes, .hours:
            guard let activeUntil else {
                return "00:00:00"
            }
            let seconds = max(0, Int(ceil(activeUntil.timeIntervalSince(now))))
            let hours = seconds / 3_600
            let minutes = seconds % 3_600 / 60
            let remainingSeconds = seconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
    }
}

@MainActor
final class KeepDisplayOnManager: ObservableObject {
    @Published private(set) var activeOption: KeepDisplayOnDuration = .off
    @Published private(set) var activeUntil: Date?

    private var process: Process?

    deinit {
        process?.terminationHandler = nil
        process?.terminate()
    }

    func activate(option: KeepDisplayOnDuration) throws {
        guard option.keepsDisplayOn else {
            stop()
            return
        }

        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")

        var arguments = ["-dimsu"]
        if let seconds = option.durationSeconds {
            arguments.append(contentsOf: ["-t", "\(seconds)"])
        }
        process.arguments = arguments

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self, self.process === terminatedProcess else {
                    return
                }
                self.clearActiveState()
            }
        }

        do {
            try process.run()
        } catch {
            clearActiveState()
            throw error
        }

        self.process = process
        activeOption = option
        if let seconds = option.durationSeconds {
            activeUntil = Date().addingTimeInterval(TimeInterval(seconds))
        } else {
            activeUntil = nil
        }
    }

    func stop() {
        guard let process else {
            clearActiveState()
            return
        }

        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        clearActiveState()
    }

    private func clearActiveState() {
        process = nil
        activeOption = .off
        activeUntil = nil
    }
}
