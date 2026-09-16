import Foundation
import MacletCore

enum KeepAwakeManagerError: LocalizedError {
    case pmsetFailed(String)
    case missingSleepDisabledValue
    case adminFailed(String)

    var errorDescription: String? {
        switch self {
        case .pmsetFailed(let message):
            return message.isEmpty ? "pmset failed." : message
        case .missingSleepDisabledValue:
            return "Could not read SleepDisabled from pmset."
        case .adminFailed(let message):
            return message.isEmpty ? "Administrator authorization failed." : message
        }
    }
}

@MainActor
final class KeepAwakeManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isChanging = false

    private let adminAuthorizationCoordinator: AdminAuthorizationCoordinator

    init(adminAuthorizationCoordinator: AdminAuthorizationCoordinator) {
        self.adminAuthorizationCoordinator = adminAuthorizationCoordinator
    }

    func refresh() async throws {
        let output = try await Self.runPmset(arguments: ["-g"])
        guard let isEnabled = Self.parseSleepDisabled(from: output) else {
            throw KeepAwakeManagerError.missingSleepDisabledValue
        }
        self.isEnabled = isEnabled
    }

    func toggle() async throws {
        try await setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) async throws {
        guard !isChanging else {
            return
        }

        isChanging = true
        defer {
            isChanging = false
        }

        let result = await adminAuthorizationCoordinator.execute(
            PrivilegedCommandRequest(
                executablePath: "/usr/bin/pmset",
                arguments: ["-a", "disablesleep", enabled ? "1" : "0"],
                timeoutSeconds: 15,
                prompt: "Maclet needs administrator access to toggle Keep Awake."
            )
        )
        guard result.succeeded else {
            try? await refresh()
            throw KeepAwakeManagerError.adminFailed(result.errorMessage)
        }

        try await refresh()
    }

    static func parseSleepDisabled(from output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.first == "SleepDisabled", let value = columns.dropFirst().first else {
                continue
            }
            return value != "0"
        }
        return nil
    }

    nonisolated private static func runPmset(arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let result = runProcess(executablePath: "/usr/bin/pmset", arguments: arguments)
            guard result.succeeded else {
                throw KeepAwakeManagerError.pmsetFailed(result.errorMessage)
            }

            return result.stdout
        }.value
    }

    nonisolated private static func runProcess(
        executablePath: String,
        arguments: [String]
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: nil, stdout: "", stderr: error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

}

private struct ProcessResult: Sendable {
    let exitCode: Int32?
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        exitCode == 0
    }

    var errorMessage: String {
        stderr.nilIfBlank ?? stdout.nilIfBlank ?? "Command failed."
    }
}
