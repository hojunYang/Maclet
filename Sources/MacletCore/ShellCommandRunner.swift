import Darwin
import Foundation

public protocol CommandRunning: Sendable {
    func run(_ command: SavedCommand) async -> CommandRunRecord
    func cancelAll()
}

public extension CommandRunning {
    func cancelAll() {}
}

public protocol AdminCommandExecuting: Sendable {
    func run(_ command: SavedCommand) async -> CommandRunRecord
    func cancelAll()
}

public extension AdminCommandExecuting {
    func cancelAll() {}
}

public final class ShellCommandRunner: CommandRunning, @unchecked Sendable {
    private let adminExecutor: AdminCommandExecuting?
    private let activeProcessesLock = NSLock()
    private var activeProcesses: [UUID: Process] = [:]
    private var cancelledCommandIDs: Set<UUID> = []

    public init(adminExecutor: AdminCommandExecuting? = nil) {
        self.adminExecutor = adminExecutor
    }

    public func run(_ command: SavedCommand) async -> CommandRunRecord {
        if command.requiresAdmin {
            if let adminExecutor {
                return await adminExecutor.run(command)
            }

            return CommandRunRecord.makeImmediateFailure(
                command: command,
                status: .adminFailed,
                stderr: "This command requires administrator authorization, but no admin executor is configured."
            )
        }

        return await runShell(command)
    }

    public func cancelAll() {
        let processes = activeProcessesLock.withLock {
            cancelledCommandIDs.formUnion(activeProcesses.keys)
            return Array(activeProcesses.values)
        }

        for process in processes where process.isRunning {
            process.terminate()
        }

        adminExecutor?.cancelAll()
    }

    private func runShell(_ command: SavedCommand) async -> CommandRunRecord {
        let task = Task.detached(priority: .userInitiated) { [self] in
            let startedAt = Date()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command.command]

            if let workingDirectory = command.workingDirectory?.nilIfBlank {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }

            var environment = ProcessInfo.processInfo.environment
            command.environment.forEach { key, value in
                environment[key] = value
            }
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutTask = Task.detached {
                stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }

            let stderrTask = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }

            guard !Task.isCancelled else {
                let finishedAt = Date()
                return CommandRunRecord(
                    commandID: command.id,
                    commandTitle: command.title,
                    command: command.command,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    duration: finishedAt.timeIntervalSince(startedAt),
                    status: .cancelled,
                    exitCode: nil,
                    stdout: "",
                    stderr: "Command was cancelled before launch."
                )
            }

            do {
                try process.run()
            } catch {
                let finishedAt = Date()
                return CommandRunRecord(
                    commandID: command.id,
                    commandTitle: command.title,
                    command: command.command,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    duration: finishedAt.timeIntervalSince(startedAt),
                    status: .failed,
                    exitCode: nil,
                    stdout: "",
                    stderr: error.localizedDescription
                )
            }

            register(process, for: command.id)
            defer {
                unregisterProcess(for: command.id)
            }

            var status: CommandRunStatus?
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    status = .cancelled
                    break
                }

                if command.timeoutSeconds > 0, Date().timeIntervalSince(startedAt) >= command.timeoutSeconds {
                    process.terminate()
                    status = .timedOut
                    break
                }

                usleep(50_000)
            }

            process.waitUntilExit()

            let stdoutData = await stdoutTask.value
            let stderrData = await stderrTask.value
            let finishedAt = Date()
            let exitCode = process.terminationStatus
            let wasCancelled = consumeCancellation(for: command.id)
            let resolvedStatus = status ?? (wasCancelled ? .cancelled : (exitCode == 0 ? .succeeded : .failed))

            return CommandRunRecord(
                commandID: command.id,
                commandTitle: command.title,
                command: command.command,
                startedAt: startedAt,
                finishedAt: finishedAt,
                duration: finishedAt.timeIntervalSince(startedAt),
                status: resolvedStatus,
                exitCode: exitCode,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            cancelProcess(for: command.id)
        }
    }

    private func register(_ process: Process, for commandID: UUID) {
        activeProcessesLock.withLock {
            activeProcesses[commandID] = process
        }
    }

    private func unregisterProcess(for commandID: UUID) {
        activeProcessesLock.withLock {
            activeProcesses[commandID] = nil
        }
    }

    private func cancelProcess(for commandID: UUID) {
        let process: Process? = activeProcessesLock.withLock { () -> Process? in
            guard let process = activeProcesses[commandID] else {
                return nil
            }
            cancelledCommandIDs.insert(commandID)
            return process
        }

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func consumeCancellation(for commandID: UUID) -> Bool {
        activeProcessesLock.withLock {
            cancelledCommandIDs.remove(commandID) != nil
        }
    }
}

extension CommandRunRecord {
    public static func makeImmediateFailure(
        command: SavedCommand,
        status: CommandRunStatus = .failed,
        stderr: String
    ) -> CommandRunRecord {
        let now = Date()
        return CommandRunRecord(
            commandID: command.id,
            commandTitle: command.title,
            command: command.command,
            startedAt: now,
            finishedAt: now,
            duration: 0,
            status: status,
            exitCode: nil,
            stdout: "",
            stderr: stderr
        )
    }
}
