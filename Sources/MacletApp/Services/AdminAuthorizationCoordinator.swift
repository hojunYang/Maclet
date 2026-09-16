import AppKit
import Foundation
import MacletCore

struct PrivilegedCommandRequest: Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL?
    let timeoutSeconds: TimeInterval
    let prompt: String

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeoutSeconds: TimeInterval,
        prompt: String
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.prompt = prompt
    }
}

enum AdminExecutionStatus: Equatable, Sendable {
    case succeeded
    case commandFailed
    case authorizationFailed
    case cancelled
    case timedOut
}

struct AdminExecutionResult: Equatable, Sendable {
    let status: AdminExecutionStatus
    let exitCode: Int32?
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        status == .succeeded
    }

    var errorMessage: String {
        stderr.nilIfBlank ?? stdout.nilIfBlank ?? "Administrator command failed."
    }
}

protocol AdminPasswordRequesting: Sendable {
    @MainActor func requestPassword(message: String) -> String?
    @MainActor func cancel()
}

@MainActor
final class AdminPasswordPromptPresenter: AdminPasswordRequesting {
    private var isPresenting = false

    func requestPassword(message: String) -> String? {
        guard !isPresenting else {
            return nil
        }

        isPresenting = true
        defer {
            isPresenting = false
        }

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        passwordField.placeholderString = "Password"
        passwordField.font = .systemFont(ofSize: 14)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Administrator Access Required"
        alert.informativeText = message
        alert.accessoryView = passwordField

        let okButton = alert.addButton(withTitle: "OK")
        okButton.isEnabled = false
        alert.addButton(withTitle: "Cancel")

        let observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: passwordField,
            queue: .main
        ) { [weak okButton, weak passwordField] _ in
            okButton?.isEnabled = !(passwordField?.stringValue.isEmpty ?? true)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        alert.window.initialFirstResponder = passwordField
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn, !passwordField.stringValue.isEmpty else {
            passwordField.stringValue = ""
            return nil
        }

        let password = passwordField.stringValue
        passwordField.stringValue = ""
        return password
    }

    func cancel() {
        guard isPresenting else {
            return
        }
        NSApp.abortModal()
    }
}

struct ProcessInvocation: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL?
    let timeoutSeconds: TimeInterval
    let standardInput: Data?

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeoutSeconds: TimeInterval,
        standardInput: Data? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.standardInput = standardInput
    }
}

enum ProcessExecutionStatus: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
    case timedOut
}

struct ProcessExecutionResult: Equatable, Sendable {
    let status: ProcessExecutionStatus
    let exitCode: Int32?
    let stdout: String
    let stderr: String

    var succeeded: Bool {
        status == .succeeded
    }

    var errorMessage: String {
        stderr.nilIfBlank ?? stdout.nilIfBlank ?? "Process failed."
    }
}

protocol PrivilegedProcessRunning: Sendable {
    func run(_ invocation: ProcessInvocation) async -> ProcessExecutionResult
    func cancelAll()
}

actor AdminAuthorizationCoordinator: AdminCommandExecuting {
    private struct AuthorizationAttempt {
        let id: UUID
        let task: Task<AuthorizationOutcome, Never>
    }

    private enum AuthorizationOutcome: Sendable {
        case authorized
        case cancelled
        case failed(String)
    }

    private let processRunner: PrivilegedProcessRunning
    private let passwordPrompt: AdminPasswordRequesting
    private var authorizationAttempt: AuthorizationAttempt?

    init(
        processRunner: PrivilegedProcessRunning = SudoProcessRunner(),
        passwordPrompt: AdminPasswordRequesting
    ) {
        self.processRunner = processRunner
        self.passwordPrompt = passwordPrompt
    }

    @MainActor
    static func live() -> AdminAuthorizationCoordinator {
        AdminAuthorizationCoordinator(passwordPrompt: AdminPasswordPromptPresenter())
    }

    func run(_ command: SavedCommand) async -> CommandRunRecord {
        let startedAt = Date()
        let workingDirectory = command.workingDirectory?.nilIfBlank.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let result = await execute(
            PrivilegedCommandRequest(
                executablePath: "/bin/zsh",
                arguments: ["-lc", command.command],
                environment: command.environment,
                workingDirectory: workingDirectory,
                timeoutSeconds: command.timeoutSeconds,
                prompt: "Maclet needs administrator access to run \(command.title)."
            )
        )
        let finishedAt = Date()

        return CommandRunRecord(
            commandID: command.id,
            commandTitle: command.title,
            command: command.command,
            startedAt: startedAt,
            finishedAt: finishedAt,
            duration: finishedAt.timeIntervalSince(startedAt),
            status: commandRunStatus(for: result.status),
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    func execute(_ request: PrivilegedCommandRequest) async -> AdminExecutionResult {
        let authorization = await authorize(prompt: request.prompt)

        switch authorization {
        case .authorized:
            break
        case .cancelled:
            return AdminExecutionResult(
                status: .cancelled,
                exitCode: nil,
                stdout: "",
                stderr: "Administrator authorization was cancelled."
            )
        case .failed(let message):
            return AdminExecutionResult(
                status: .authorizationFailed,
                exitCode: nil,
                stdout: "",
                stderr: message
            )
        }

        guard !Task.isCancelled else {
            return AdminExecutionResult(
                status: .cancelled,
                exitCode: nil,
                stdout: "",
                stderr: "Administrator command was cancelled."
            )
        }

        let processResult = await processRunner.run(sudoInvocation(for: request))
        return adminResult(from: processResult, failureStatus: .commandFailed)
    }

    nonisolated func cancelAll() {
        processRunner.cancelAll()
        Task { @MainActor [passwordPrompt] in
            passwordPrompt.cancel()
        }
        Task {
            await cancelAuthorizationAttempt()
        }
    }

    private func authorize(prompt: String) async -> AuthorizationOutcome {
        let cachedResult = await processRunner.run(
            ProcessInvocation(
                executablePath: "/usr/bin/sudo",
                arguments: ["-n", "-v"],
                timeoutSeconds: 5
            )
        )

        if cachedResult.succeeded {
            return .authorized
        }

        if cachedResult.status == .cancelled || Task.isCancelled {
            return .cancelled
        }

        if cachedResult.exitCode == nil {
            return .failed(cachedResult.errorMessage)
        }

        if let authorizationAttempt {
            return await authorizationAttempt.task.value
        }

        let attemptID = UUID()
        let processRunner = self.processRunner
        let passwordPrompt = self.passwordPrompt
        let task = Task<AuthorizationOutcome, Never> {
            guard !Task.isCancelled else {
                return .cancelled
            }

            guard let password = await passwordPrompt.requestPassword(message: prompt) else {
                return .cancelled
            }

            guard !Task.isCancelled else {
                return .cancelled
            }

            let validationResult = await processRunner.run(
                ProcessInvocation(
                    executablePath: "/usr/bin/sudo",
                    arguments: ["-S", "-p", "", "-v"],
                    timeoutSeconds: 15,
                    standardInput: Data((password + "\n").utf8)
                )
            )

            if validationResult.succeeded {
                return .authorized
            }

            if validationResult.status == .cancelled || Task.isCancelled {
                return .cancelled
            }

            return .failed(validationResult.errorMessage)
        }

        authorizationAttempt = AuthorizationAttempt(id: attemptID, task: task)
        let outcome = await task.value
        if authorizationAttempt?.id == attemptID {
            authorizationAttempt = nil
        }
        return outcome
    }

    private func sudoInvocation(for request: PrivilegedCommandRequest) -> ProcessInvocation {
        var arguments = ["-n", "--"]

        if request.environment.isEmpty {
            arguments.append(request.executablePath)
        } else {
            arguments.append("/usr/bin/env")
            arguments.append(contentsOf: request.environment
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" })
            arguments.append(request.executablePath)
        }

        arguments.append(contentsOf: request.arguments)
        return ProcessInvocation(
            executablePath: "/usr/bin/sudo",
            arguments: arguments,
            workingDirectory: request.workingDirectory,
            timeoutSeconds: request.timeoutSeconds
        )
    }

    private func adminResult(
        from result: ProcessExecutionResult,
        failureStatus: AdminExecutionStatus
    ) -> AdminExecutionResult {
        let status: AdminExecutionStatus
        switch result.status {
        case .succeeded:
            status = .succeeded
        case .failed:
            status = failureStatus
        case .cancelled:
            status = .cancelled
        case .timedOut:
            status = .timedOut
        }

        return AdminExecutionResult(
            status: status,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    private func commandRunStatus(for status: AdminExecutionStatus) -> CommandRunStatus {
        switch status {
        case .succeeded:
            return .succeeded
        case .commandFailed:
            return .failed
        case .authorizationFailed:
            return .adminFailed
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        }
    }

    private func cancelAuthorizationAttempt() {
        authorizationAttempt?.task.cancel()
        authorizationAttempt = nil
    }
}

final class SudoProcessRunner: PrivilegedProcessRunning, @unchecked Sendable {
    private let activeProcessesLock = NSLock()
    private var activeProcesses: [UUID: Process] = [:]
    private var cancelledProcessIDs: Set<UUID> = []

    func run(_ invocation: ProcessInvocation) async -> ProcessExecutionResult {
        let processID = UUID()
        let task = Task.detached(priority: .userInitiated) { [self] in
            await execute(invocation, processID: processID)
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            cancelProcess(processID)
        }
    }

    func cancelAll() {
        let processes = activeProcessesLock.withLock {
            cancelledProcessIDs.formUnion(activeProcesses.keys)
            return Array(activeProcesses.values)
        }

        for process in processes where process.isRunning {
            process.terminate()
        }
    }

    private func execute(
        _ invocation: ProcessInvocation,
        processID: UUID
    ) async -> ProcessExecutionResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executablePath)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory

        var environment = ProcessInfo.processInfo.environment
        invocation.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = invocation.standardInput == nil ? nil : Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe ?? FileHandle.nullDevice

        guard !Task.isCancelled else {
            return ProcessExecutionResult(
                status: .cancelled,
                exitCode: nil,
                stdout: "",
                stderr: "Process was cancelled before launch."
            )
        }

        do {
            try process.run()
        } catch {
            return ProcessExecutionResult(
                status: .failed,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        register(process, for: processID)
        defer {
            unregisterProcess(for: processID)
        }

        if let standardInput = invocation.standardInput, let stdinPipe {
            stdinPipe.fileHandleForWriting.write(standardInput)
            try? stdinPipe.fileHandleForWriting.close()
        }

        let stdoutTask = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        var status: ProcessExecutionStatus?
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                status = .cancelled
                break
            }

            if invocation.timeoutSeconds > 0,
               Date().timeIntervalSince(startedAt) >= invocation.timeoutSeconds {
                process.terminate()
                status = .timedOut
                break
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        process.waitUntilExit()

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        let exitCode = process.terminationStatus
        let wasCancelled = consumeCancellation(for: processID)
        let resolvedStatus = status
            ?? (wasCancelled ? .cancelled : (exitCode == 0 ? .succeeded : .failed))

        return ProcessExecutionResult(
            status: resolvedStatus,
            exitCode: exitCode,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func register(_ process: Process, for processID: UUID) {
        activeProcessesLock.withLock {
            activeProcesses[processID] = process
        }
    }

    private func unregisterProcess(for processID: UUID) {
        activeProcessesLock.withLock {
            activeProcesses[processID] = nil
        }
    }

    private func cancelProcess(_ processID: UUID) {
        let process: Process? = activeProcessesLock.withLock { () -> Process? in
            guard let process = activeProcesses[processID] else {
                return nil
            }
            cancelledProcessIDs.insert(processID)
            return process
        }

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func consumeCancellation(for processID: UUID) -> Bool {
        activeProcessesLock.withLock {
            cancelledProcessIDs.remove(processID) != nil
        }
    }
}
