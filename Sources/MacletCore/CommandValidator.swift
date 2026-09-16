import Foundation

public enum CommandValidationError: LocalizedError, Equatable, Sendable {
    case emptyTitle
    case emptyCommand
    case timeoutTooSmall
    case timeoutTooLarge
    case invalidWorkingDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "A command needs a title."
        case .emptyCommand:
            return "A command needs shell text to run."
        case .timeoutTooSmall:
            return "Timeout must be at least 1 second."
        case .timeoutTooLarge:
            return "Timeout cannot be more than 24 hours."
        case .invalidWorkingDirectory(let path):
            return "Working directory does not exist: \(path)"
        }
    }
}

public enum CommandValidator {
    public static func validate(_ command: SavedCommand, fileManager: FileManager = .default) throws {
        if command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CommandValidationError.emptyTitle
        }

        if command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CommandValidationError.emptyCommand
        }

        if command.timeoutSeconds < 1 {
            throw CommandValidationError.timeoutTooSmall
        }

        if command.timeoutSeconds > 86_400 {
            throw CommandValidationError.timeoutTooLarge
        }

        if let workingDirectory = command.workingDirectory?.nilIfBlank {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: workingDirectory, isDirectory: &isDirectory) || !isDirectory.boolValue {
                throw CommandValidationError.invalidWorkingDirectory(workingDirectory)
            }
        }
    }
}

extension String {
    public var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
