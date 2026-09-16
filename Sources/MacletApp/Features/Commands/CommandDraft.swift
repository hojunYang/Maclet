import Foundation
import MacletCore

struct CommandDraft: Identifiable {
    var id: UUID
    var title: String
    var symbolName: String
    var command: String
    var workingDirectory: String
    var environmentText: String
    var timeoutSeconds: Double
    var requiresConfirmation: Bool
    var requiresAdmin: Bool
    var isFavorite: Bool
    var createdAt: Date
    var lastRun: CommandRunSummary?

    init() {
        id = UUID()
        title = ""
        symbolName = "terminal"
        command = ""
        workingDirectory = ""
        environmentText = ""
        timeoutSeconds = 30
        requiresConfirmation = false
        requiresAdmin = false
        isFavorite = true
        createdAt = Date()
        lastRun = nil
    }

    init(command: SavedCommand) {
        id = command.id
        title = command.title
        symbolName = command.symbolName
        self.command = command.command
        workingDirectory = command.workingDirectory ?? ""
        environmentText = command.environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        timeoutSeconds = command.timeoutSeconds
        requiresConfirmation = command.requiresConfirmation
        requiresAdmin = command.requiresAdmin
        isFavorite = command.isFavorite
        createdAt = command.createdAt
        lastRun = command.lastRun
    }

    func makeCommand() throws -> SavedCommand {
        SavedCommand(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "terminal",
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectory: workingDirectory.nilIfBlank,
            environment: try parseEnvironment(environmentText),
            timeoutSeconds: timeoutSeconds,
            requiresConfirmation: requiresConfirmation,
            requiresAdmin: requiresAdmin,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: Date(),
            lastRun: lastRun
        )
    }

    private func parseEnvironment(_ text: String) throws -> [String: String] {
        var environment: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                throw DraftError.invalidEnvironmentLine(line)
            }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separatorIndex)...])

            guard !key.isEmpty else {
                throw DraftError.invalidEnvironmentLine(line)
            }

            environment[key] = value
        }

        return environment
    }
}

enum DraftError: LocalizedError {
    case invalidEnvironmentLine(String)

    var errorDescription: String? {
        switch self {
        case .invalidEnvironmentLine(let line):
            return "Environment lines must look like KEY=value. Invalid line: \(line)"
        }
    }
}
