import XCTest
@testable import MacletCore

final class ShellCommandRunnerTests: XCTestCase {
    func testSuccessfulCommandCapturesStdout() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(title: "Echo", command: "echo hello", timeoutSeconds: 5)

        let record = await runner.run(command)

        XCTAssertEqual(record.status, .succeeded)
        XCTAssertEqual(record.exitCode, 0)
        XCTAssertEqual(record.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(record.stderr, "")
    }

    func testFailingCommandCapturesExitCodeAndStderr() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(title: "Fail", command: "echo nope >&2; exit 7", timeoutSeconds: 5)

        let record = await runner.run(command)

        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.exitCode, 7)
        XCTAssertEqual(record.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "nope")
    }

    func testTimeoutTerminatesCommand() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(title: "Sleep", command: "sleep 2", timeoutSeconds: 0.2)

        let record = await runner.run(command)

        XCTAssertEqual(record.status, .timedOut)
        XCTAssertLessThan(record.duration, 2)
    }

    func testTaskCancellationTerminatesCommand() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(title: "Sleep", command: "sleep 5", timeoutSeconds: 10)

        let task = Task {
            await runner.run(command)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let record = await task.value

        XCTAssertEqual(record.status, .cancelled)
        XCTAssertLessThan(record.duration, 5)
    }

    func testEnvironmentIsMerged() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(
            title: "Env",
            command: "printf \"$MACLET_TEST_VALUE\"",
            environment: ["MACLET_TEST_VALUE": "ok"],
            timeoutSeconds: 5
        )

        let record = await runner.run(command)

        XCTAssertEqual(record.status, .succeeded)
        XCTAssertEqual(record.stdout, "ok")
    }

    func testAdminCommandFailsWithoutAdminExecutor() async {
        let runner = ShellCommandRunner()
        let command = SavedCommand(title: "Admin", command: "pmset -g", requiresAdmin: true)

        let record = await runner.run(command)

        XCTAssertEqual(record.status, .adminFailed)
        XCTAssertTrue(record.stderr.contains("administrator"))
    }
}
