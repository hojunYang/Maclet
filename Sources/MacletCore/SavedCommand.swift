import Foundation

public struct SavedCommand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var symbolName: String
    public var command: String
    public var workingDirectory: String?
    public var environment: [String: String]
    public var timeoutSeconds: TimeInterval
    public var requiresConfirmation: Bool
    public var requiresAdmin: Bool
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastRun: CommandRunSummary?

    public init(
        id: UUID = UUID(),
        title: String,
        symbolName: String = "terminal",
        command: String,
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 30,
        requiresConfirmation: Bool = false,
        requiresAdmin: Bool = false,
        isFavorite: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastRun: CommandRunSummary? = nil
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.requiresConfirmation = requiresConfirmation
        self.requiresAdmin = requiresAdmin
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRun = lastRun
    }

    public var displayWorkingDirectory: String {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return "~"
        }
        return workingDirectory
    }
}

public struct CommandRunSummary: Codable, Equatable, Sendable {
    public var status: CommandRunStatus
    public var exitCode: Int32?
    public var finishedAt: Date
    public var duration: TimeInterval

    public init(status: CommandRunStatus, exitCode: Int32?, finishedAt: Date, duration: TimeInterval) {
        self.status = status
        self.exitCode = exitCode
        self.finishedAt = finishedAt
        self.duration = duration
    }
}

public enum CommandPresets {
    public static let defaults: [SavedCommand] = [
        SavedCommand(
            title: "Battery Info",
            symbolName: "battery.75percent",
            command: "pmset -g batt",
            timeoutSeconds: 10,
            isFavorite: true
        ),
        SavedCommand(
            title: "Keep Display On 1h",
            symbolName: "moon.zzz",
            command: "caffeinate -dimsu -t 3600",
            timeoutSeconds: 3610,
            requiresConfirmation: true,
            isFavorite: true
        ),
        SavedCommand(
            title: "List Shortcuts",
            symbolName: "sparkles",
            command: "shortcuts list",
            timeoutSeconds: 15,
            isFavorite: true
        ),
        SavedCommand(
            title: "Private Relay Settings",
            symbolName: "icloud",
            command: "open \"x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane\"",
            timeoutSeconds: 10,
            isFavorite: true
        ),
        SavedCommand(
            title: "Keep Awake",
            symbolName: "lock.shield",
            command: "pmset -a sleep 0",
            timeoutSeconds: 15,
            requiresConfirmation: true,
            requiresAdmin: true,
            isFavorite: false
        )
    ]
}
