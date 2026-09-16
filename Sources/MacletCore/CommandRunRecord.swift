import Foundation

public struct CommandRunRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var commandID: UUID
    public var commandTitle: String
    public var command: String
    public var startedAt: Date
    public var finishedAt: Date
    public var duration: TimeInterval
    public var status: CommandRunStatus
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String

    public init(
        id: UUID = UUID(),
        commandID: UUID,
        commandTitle: String,
        command: String,
        startedAt: Date,
        finishedAt: Date,
        duration: TimeInterval,
        status: CommandRunStatus,
        exitCode: Int32?,
        stdout: String,
        stderr: String
    ) {
        self.id = id
        self.commandID = commandID
        self.commandTitle = commandTitle
        self.command = command
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var summary: CommandRunSummary {
        CommandRunSummary(
            status: status,
            exitCode: exitCode,
            finishedAt: finishedAt,
            duration: duration
        )
    }
}

public enum CommandRunStatus: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed
    case timedOut
    case cancelled
    case adminFailed

    public var isSuccess: Bool {
        self == .succeeded
    }
}
