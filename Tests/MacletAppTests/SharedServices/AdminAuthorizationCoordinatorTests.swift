import Foundation
import XCTest
@testable import MacletApp

final class AdminAuthorizationCoordinatorTests: XCTestCase {
    @MainActor
    func testPasswordPromptIsPresentedAsCurrentApplicationModal() {
        _ = NSApplication.shared
        let presenter = AdminPasswordPromptPresenter()
        let observation = ModalWindowObservation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            observation.wasPresentedAsModal = NSApp.modalWindow != nil
            presenter.cancel()
        }

        let password = presenter.requestPassword(message: "Authorization required")

        XCTAssertNil(password)
        XCTAssertTrue(observation.wasPresentedAsModal)
    }

    @MainActor
    func testCachedAuthorizationRunsCommandWithoutPrompt() async {
        let processRunner = StubPrivilegedProcessRunner(results: [
            .success(),
            .success(stdout: "0\n")
        ])
        let passwordPrompt = StubAdminPasswordPrompt(responses: [])
        let coordinator = AdminAuthorizationCoordinator(
            processRunner: processRunner,
            passwordPrompt: passwordPrompt
        )

        let result = await coordinator.execute(testRequest())

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.stdout, "0\n")
        XCTAssertTrue(passwordPrompt.messages.isEmpty)
        XCTAssertEqual(processRunner.invocations.count, 2)
        XCTAssertEqual(processRunner.invocations[0].arguments, ["-n", "-v"])
        XCTAssertEqual(
            processRunner.invocations[1].arguments,
            ["-n", "--", "/usr/bin/id", "-u"]
        )
    }

    @MainActor
    func testMissingCachePromptsValidatesAndRunsCommand() async {
        let processRunner = StubPrivilegedProcessRunner(results: [
            .failure(exitCode: 1, stderr: "password required"),
            .success(),
            .success(stdout: "0\n")
        ])
        let passwordPrompt = StubAdminPasswordPrompt(responses: ["secret"])
        let coordinator = AdminAuthorizationCoordinator(
            processRunner: processRunner,
            passwordPrompt: passwordPrompt
        )

        let result = await coordinator.execute(testRequest())

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(passwordPrompt.messages, ["Authorization required"])
        XCTAssertEqual(processRunner.invocations.count, 3)
        XCTAssertEqual(processRunner.invocations[1].arguments, ["-S", "-p", "", "-v"])
        XCTAssertEqual(processRunner.invocations[1].standardInput, Data("secret\n".utf8))
        XCTAssertEqual(
            processRunner.invocations[2].arguments,
            ["-n", "--", "/usr/bin/id", "-u"]
        )
    }

    @MainActor
    func testCancelledPromptDoesNotRunCommand() async {
        let processRunner = StubPrivilegedProcessRunner(results: [
            .failure(exitCode: 1, stderr: "password required")
        ])
        let passwordPrompt = StubAdminPasswordPrompt(responses: [nil])
        let coordinator = AdminAuthorizationCoordinator(
            processRunner: processRunner,
            passwordPrompt: passwordPrompt
        )

        let result = await coordinator.execute(testRequest())

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(processRunner.invocations.count, 1)
    }

    private func testRequest() -> PrivilegedCommandRequest {
        PrivilegedCommandRequest(
            executablePath: "/usr/bin/id",
            arguments: ["-u"],
            timeoutSeconds: 5,
            prompt: "Authorization required"
        )
    }
}

@MainActor
private final class ModalWindowObservation {
    var wasPresentedAsModal = false
}

@MainActor
private final class StubAdminPasswordPrompt: AdminPasswordRequesting {
    private var responses: [String?]
    private(set) var messages: [String] = []

    init(responses: [String?]) {
        self.responses = responses
    }

    func requestPassword(message: String) -> String? {
        messages.append(message)
        guard !responses.isEmpty else {
            return nil
        }
        return responses.removeFirst()
    }

    func cancel() {}
}

private final class StubPrivilegedProcessRunner: PrivilegedProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedResults: [ProcessExecutionResult]
    private var recordedInvocations: [ProcessInvocation] = []

    var invocations: [ProcessInvocation] {
        lock.withLock { recordedInvocations }
    }

    init(results: [ProcessExecutionResult]) {
        queuedResults = results
    }

    func run(_ invocation: ProcessInvocation) async -> ProcessExecutionResult {
        lock.withLock {
            recordedInvocations.append(invocation)
            guard !queuedResults.isEmpty else {
                return .failure(exitCode: nil, stderr: "Unexpected process invocation")
            }
            return queuedResults.removeFirst()
        }
    }

    func cancelAll() {}
}

private extension ProcessExecutionResult {
    static func success(stdout: String = "") -> ProcessExecutionResult {
        ProcessExecutionResult(
            status: .succeeded,
            exitCode: 0,
            stdout: stdout,
            stderr: ""
        )
    }

    static func failure(exitCode: Int32?, stderr: String) -> ProcessExecutionResult {
        ProcessExecutionResult(
            status: .failed,
            exitCode: exitCode,
            stdout: "",
            stderr: stderr
        )
    }
}
